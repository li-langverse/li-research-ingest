#!/usr/bin/env bash
# Full arXiv OAI-PMH harvest (no setSpec) — sharded pages + resumption resume.

set -euo pipefail

harvest_arxiv_full_corpus() {
  local max_records="${1:-0}"
  local pages_dir="${ARXIV_FULL_OUTPUT_DIR}"
  local state_file="$ARXIV_OUTPUT_DIR/full/.cursor-state.json"
  local complete_marker="$ARXIV_OUTPUT_DIR/full/.full.ok"

  mkdir -p "$pages_dir" "$ARXIV_OUTPUT_DIR/full"

  if [[ -f "$complete_marker" ]]; then
    log "skip arXiv full corpus — already complete"
    return 0
  fi

  local token=""
  local page=0
  local total_records=0

  if [[ -f "$state_file" ]]; then
    token="$(jq -r '.resumption_token // empty' "$state_file" 2>/dev/null || true)"
    page="$(jq -r '.page // 0' "$state_file" 2>/dev/null || echo 0)"
    total_records="$(jq -r '.total_records // 0' "$state_file" 2>/dev/null || echo 0)"
    [[ "$token" == "null" ]] && token=""
    page=$((page + 0))
    total_records=$((total_records + 0))
    if [[ -n "$token" ]]; then
      log "arXiv full resume from page ${page} (${total_records} records so far)"
    fi
  fi

  while :; do
    page=$((page + 1))
    local query
    if [[ -n "$token" ]]; then
      query="${ARXIV_OAI_ENDPOINT}?verb=ListRecords&resumptionToken=${token}"
    else
      query="${ARXIV_OAI_ENDPOINT}?verb=ListRecords&metadataPrefix=${ARXIV_METADATA_PREFIX}"
    fi

    local out_file="$pages_dir/page-$(printf '%07d' "$page").xml"
    if [[ -f "$out_file" ]]; then
      log "arXiv full resume skip page $page (exists)"
      token="$(jq -r --arg p "$page" 'if .page == ($p|tonumber) then .next_token else empty end' "$state_file" 2>/dev/null || true)"
      if [[ -z "$token" || "$token" == "null" ]]; then
        log "arXiv full: missing next token after skip — refetch page $page"
      else
        sleep "$ARXIV_REQUEST_INTERVAL"
        continue
      fi
    fi

    log "arXiv full OAI page $page (total_records=${total_records})"
    local tmp
    tmp="$(mktemp)"
    if ! curl -fsSL --retry 3 --retry-delay 5 -o "$tmp" "$query"; then
      rm -f "$tmp"
      echo "arXiv full OAI fetch failed on page $page" >&2
      return 1
    fi

    local page_records=0
    page_records="$(oai_count_records "$tmp")"
    page_records=$((page_records + 0))
    if [[ "$page_records" -gt 0 ]]; then
      cp "$tmp" "$out_file"
      total_records=$((total_records + page_records))
    else
      cp "$tmp" "$out_file"
    fi

    token="$(oai_resumption_token "$tmp")"
    rm -f "$tmp"

    require_cmd jq
    jq -n \
      --argjson page "$page" \
      --arg resumption_token "${token:-}" \
      --arg next_token "${token:-}" \
      --argjson total_records "$total_records" \
      --argjson page_records "$page_records" \
      --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '{
        page: $page,
        resumption_token: (if $resumption_token == "" then null else $resumption_token end),
        next_token: (if $next_token == "" then null else $next_token end),
        total_records: $total_records,
        last_page_records: $page_records,
        updated_at: $updated_at
      }' >"$state_file"

    if [[ "$max_records" -gt 0 && "$total_records" -ge "$max_records" ]]; then
      log "arXiv full: reached max-records=$max_records"
      break
    fi

    if [[ -z "$token" || "$token" == "null" ]]; then
      date -u +"%Y-%m-%dT%H:%M:%SZ" >"$complete_marker"
      log "arXiv full corpus complete — ${total_records} records in ${page} pages"
      break
    fi

    sleep "$ARXIV_REQUEST_INTERVAL"
  done

  printf 'scope\tfull\nrecords\t%s\npages\t%s\n' "$total_records" "$page" >"$ARXIV_OUTPUT_DIR/full/.harvest-summary.txt"
}
