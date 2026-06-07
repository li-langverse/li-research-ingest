#!/usr/bin/env bash
# Resume-safe ingest state + staging manifest for /warm-index.

set -euo pipefail

INGEST_STATE_FILE="${WARM_INDEX_STAGING}/.ingest-run-state.json"
INGEST_MANIFEST_FILE="${WARM_INDEX_STAGING}/manifest.json"

_dir_bytes() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo 0
    return
  fi
  local raw
  raw="$(du -sb "$dir" 2>/dev/null | awk '{print $1}' || echo 0)"
  raw="${raw:-0}"
  if [[ ! "$raw" =~ ^[0-9]+$ ]]; then
    echo 0
    return
  fi
  echo "$raw"
}

_count_data_files() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo 0
    return
  fi
  find "$dir" -type f \( -name '*.gz' -o -name '*.jsonl' -o -name '*.jsonl.gz' -o -name '*.parquet' -o -name '*.xml' \) 2>/dev/null | wc -l | tr -d ' '
}

_s2_release_marker() {
  local dataset="$1"
  local dir="$2"
  local marker="$dir/.release-${S2_RELEASE}-${dataset}.ok"
  if [[ -f "$marker" ]]; then
    echo complete
  elif [[ "$(_count_data_files "$dir")" -gt 0 ]]; then
    echo partial
  else
    echo pending
  fi
}

_arxiv_status() {
  if [[ ! -d "$ARXIV_OUTPUT_DIR" ]]; then
    echo pending
    return
  fi
  local markers total=0 done=0
  mapfile -t sets < <(toml_array_values arxiv sets)
  for set_spec in "${sets[@]}"; do
    set_spec="$(printf '%s' "$set_spec" | xargs)"
    [[ -z "$set_spec" ]] && continue
    total=$((total + 1))
    local safe_name
    safe_name="$(printf '%s' "$set_spec" | tr ':/' '__')"
    [[ -f "$ARXIV_OUTPUT_DIR/.${safe_name}.ok" ]] && done=$((done + 1))
  done
  if [[ "$total" -eq 0 ]]; then
    echo pending
  elif [[ "$done" -eq "$total" ]]; then
    echo complete
  elif [[ "$done" -gt 0 || "$(_count_data_files "$ARXIV_OUTPUT_DIR")" -gt 0 ]]; then
    echo partial
  else
    echo pending
  fi
}

write_ingest_run_state() {
  require_cmd jq

  local bytes_s2 bytes_arxiv bytes_total min_bytes gate_passed
  local s2_root="${WARM_INDEX_STAGING}/s2"
  bytes_s2="$(_dir_bytes "$s2_root")"
  bytes_arxiv="$(_dir_bytes "$ARXIV_OUTPUT_DIR")"
  bytes_total=$((bytes_s2 + bytes_arxiv))
  min_bytes="${WARM_INGEST_MIN_BYTES:-1073741824}"
  gate_passed=false
  if (( bytes_s2 >= min_bytes )); then
    gate_passed=true
  fi

  local s2_key_status="missing"
  [[ -n "${S2_API_KEY:-}" ]] && s2_key_status="present"

  local agent_run_id="${LI_AGENT_RUN_ID:-}"
  if [[ -z "$agent_run_id" && -n "${LI_REPO_WORKFLOW_WORKSPACE:-}" ]]; then
    agent_run_id="$(basename "$(dirname "$LI_REPO_WORKFLOW_WORKSPACE")")"
  fi

  local s2_abs_status s2_pap_status arx_status
  local abs_files pap_files arx_files
  s2_abs_status=$(_s2_release_marker abstracts "$S2_ABSTRACTS_DIR")
  s2_pap_status=$(_s2_release_marker papers "$S2_PAPERS_DIR")
  arx_status=$(_arxiv_status)
  abs_files=$(_count_data_files "$S2_ABSTRACTS_DIR")
  pap_files=$(_count_data_files "$S2_PAPERS_DIR")
  arx_files=$(_count_data_files "$ARXIV_OUTPUT_DIR")

  jq -n \
    --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg warm_index_root "$WARM_INDEX_ROOT" \
    --argjson bytes_s2 "$bytes_s2" \
    --argjson bytes_arxiv "$bytes_arxiv" \
    --argjson bytes_total "$bytes_total" \
    --argjson min_bytes_gate "$min_bytes" \
    --argjson gate_passed "$gate_passed" \
    --arg s2_api_key "$s2_key_status" \
    --arg agent_run_id "$agent_run_id" \
    --arg s2_abstracts_status "$s2_abs_status" \
    --arg s2_papers_status "$s2_pap_status" \
    --arg arxiv_status "$arx_status" \
    --argjson s2_abstracts_files "$abs_files" \
    --argjson s2_papers_files "$pap_files" \
    --argjson arxiv_files "$arx_files" \
    '{
      updated_at: $updated_at,
      warm_index_root: $warm_index_root,
      bytes: { s2: $bytes_s2, arxiv: $bytes_arxiv, total: $bytes_total },
      min_bytes_gate: $min_bytes_gate,
      gate_passed: $gate_passed,
      s2_api_key: $s2_api_key,
      agent_run_id: (if $agent_run_id == "" then null else $agent_run_id end),
      datasets: {
        s2_abstracts: { status: $s2_abstracts_status, files: $s2_abstracts_files },
        s2_papers: { status: $s2_papers_status, files: $s2_papers_files },
        arxiv_oai: { status: $arxiv_status, files: $arxiv_files }
      }
    }' >"$INGEST_STATE_FILE"

  log "ingest state: $INGEST_STATE_FILE (s2=${bytes_s2} bytes, gate=${gate_passed})"
}

write_staging_manifest() {
  require_cmd jq

  local entries=()
  local dir kind file rel sha size

  add_partition_files() {
    local scan_dir="$1"
    local scan_kind="$2"
    [[ -d "$scan_dir" ]] || return 0
    while IFS= read -r -d '' file; do
      rel="${file#${WARM_INDEX_STAGING}/}"
      size="$(stat -c '%s' "$file" 2>/dev/null || echo 0)"
      if command -v sha256sum >/dev/null 2>&1; then
        sha="$(sha256sum "$file" | awk '{print $1}')"
      else
        sha=""
      fi
      entries+=("$(jq -nc \
        --arg kind "$scan_kind" \
        --arg path "$rel" \
        --arg sha256 "$sha" \
        --argjson bytes "$size" \
        '{kind: $kind, path: $path, sha256: $sha256, bytes: $bytes}')")
    done < <(find "$scan_dir" -type f \( -name '*.gz' -o -name '*.jsonl' -o -name '*.jsonl.gz' -o -name '*.parquet' -o -name '*.xml' \) -print0 2>/dev/null)
  }

  add_partition_files "$S2_ABSTRACTS_DIR" "s2_abstracts"
  add_partition_files "$S2_PAPERS_DIR" "s2_papers"
  add_partition_files "$ARXIV_OUTPUT_DIR" "arxiv_oai"

  local joined=""
  if [[ "${#entries[@]}" -gt 0 ]]; then
    joined="$(printf '%s\n' "${entries[@]}" | jq -s '.')"
  else
    joined="[]"
  fi

  jq -n \
    --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg warm_index_root "$WARM_INDEX_ROOT" \
    --argjson partitions "$joined" \
    --argjson partition_count "$(printf '%s' "$joined" | jq 'length')" \
    '{
      generated_at: $generated_at,
      warm_index_root: $warm_index_root,
      partition_count: $partition_count,
      partitions: $partitions
    }' >"$INGEST_MANIFEST_FILE"

  log "staging manifest: $INGEST_MANIFEST_FILE (${#entries[@]} partitions)"
}

s2_bytes() {
  local s2_root="${WARM_INDEX_STAGING}/s2"
  _dir_bytes "$s2_root"
}
