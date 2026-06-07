#!/usr/bin/env bash
# Download a Semantic Scholar dataset release partition set.

set -euo pipefail

_s2_download_partition() {
  local file_url="$1"
  local dest_dir="$2"
  local fail_flag="$3"

  local base
  base="$(basename "$file_url" | cut -d'?' -f1)"
  local target="$dest_dir/$base"

  if [[ -f "$target" ]]; then
    log "resume skip (exists): $base"
    return 0
  fi

  log "downloading: $base"
  if ! curl -fsSL --retry 3 --retry-delay 5 -o "$target.part" "$file_url"; then
    rm -f "$target.part"
    touch "$fail_flag"
    return 1
  fi
  mv "$target.part" "$target"
  local fsize
  fsize="$(stat -c '%s' "$target" 2>/dev/null || echo 0)"
  log "saved $base (${fsize} bytes; dir=$(du -sb "$dest_dir" 2>/dev/null | awk '{print $1}'))"
}

s2_download_dataset() {
  local dataset="$1"
  local dest_dir="$2"
  local max_files="${3:-0}"

  if [[ -z "${S2_API_KEY:-}" ]]; then
    echo "S2_API_KEY is required for dataset download ($dataset)" >&2
    echo "Set S2_API_KEY or run with --bootstrap on the ingest script." >&2
    exit 1
  fi

  require_cmd curl
  require_cmd jq

  mkdir -p "$dest_dir"
  local marker="$dest_dir/.release-${S2_RELEASE}-${dataset}.ok"
  if [[ -f "$marker" ]]; then
    log "skip $dataset — marker present: $marker"
    return 0
  fi

  local url="${S2_API_BASE}/release/${S2_RELEASE}/dataset/${dataset}"
  log "fetching S2 download links: $url"
  local payload
  payload="$(curl -fsSL -H "x-api-key: ${S2_API_KEY}" "$url")"

  local release_id
  release_id="$(printf '%s' "$payload" | jq -r '.release_id // empty')"
  if [[ -n "$release_id" && "$release_id" != "null" ]]; then
    log "S2 release_id: $release_id"
  fi

  local -a file_urls=()
  while IFS= read -r file_url; do
    [[ -z "$file_url" || "$file_url" == "null" ]] && continue
    file_urls+=("$file_url")
  done < <(printf '%s' "$payload" | jq -r '.files[]?')

  local file_count="${#file_urls[@]}"
  if [[ "$file_count" -eq 0 ]]; then
    echo "no files returned for dataset $dataset" >&2
    exit 1
  fi

  local parallel="${S2_DOWNLOAD_PARALLEL:-2}"
  if [[ "$parallel" -lt 1 ]]; then
    parallel=1
  fi
  log "S2 $dataset: ${file_count} partitions (parallel=${parallel}, max_files=${max_files:-all})"

  local fail_flag
  fail_flag="$(mktemp "${TMPDIR:-/tmp}/s2-dl-fail.XXXXXX")"
  local downloaded=0 queued=0 active=0

  for file_url in "${file_urls[@]}"; do
    if [[ "$max_files" -gt 0 && "$downloaded" -ge "$max_files" ]]; then
      log "reached max_files=$max_files for $dataset"
      break
    fi

    local base
    base="$(basename "$file_url" | cut -d'?' -f1)"
    if [[ -f "$dest_dir/$base" ]]; then
      downloaded=$((downloaded + 1))
      continue
    fi

    _s2_download_partition "$file_url" "$dest_dir" "$fail_flag" &
    active=$((active + 1))
    queued=$((queued + 1))
    downloaded=$((downloaded + 1))

    while [[ "$active" -ge "$parallel" ]]; do
      if ! wait -n; then
        touch "$fail_flag"
      fi
      active=$((active - 1))
    done
  done

  while [[ "$active" -gt 0 ]]; do
    if ! wait -n; then
      touch "$fail_flag"
    fi
    active=$((active - 1))
  done

  if [[ -f "$fail_flag" ]]; then
    rm -f "$fail_flag"
    echo "S2 download failed for dataset $dataset" >&2
    return 1
  fi
  rm -f "$fail_flag"

  {
    echo "dataset=$dataset"
    echo "release=${S2_RELEASE}"
    echo "files_listed=$file_count"
    echo "files_downloaded=$downloaded"
    echo "parallel=$parallel"
    echo "completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } >"$marker"
  log "finished $dataset → $dest_dir ($downloaded files)"
}

# Public sample shards (no API key) — smoke only; far below R1b 1 GiB gate.
s2_download_samples() {
  local dataset="$1"
  local dest_dir="$2"

  require_cmd curl

  local sample_base="https://ai2-s2ag.s3-us-west-2.amazonaws.com/samples"
  local sample_file=""
  case "$dataset" in
    abstracts) sample_file="abstracts/abstracts-sample.jsonl.gz" ;;
    papers) sample_file="papers/papers-sample.jsonl.gz" ;;
    *)
      echo "no public sample for dataset: $dataset" >&2
      return 1
      ;;
  esac

  mkdir -p "$dest_dir"
  local target="$dest_dir/$(basename "$sample_file")"
  if [[ -f "$target" ]]; then
    log "sample already present: $target"
    return 0
  fi

  log "downloading S2 sample ($dataset): $sample_file"
  curl -fsSL --retry 3 --retry-delay 5 \
    "${sample_base}/${sample_file}" -o "$target.part"
  mv "$target.part" "$target"
  log "sample saved: $target"
}
