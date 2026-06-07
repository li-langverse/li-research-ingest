#!/usr/bin/env bash
# Download a Semantic Scholar dataset release partition set.

set -euo pipefail

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

  local file_count=0
  local downloaded=0
  local bytes_downloaded=0
  while IFS= read -r file_url; do
    [[ -z "$file_url" || "$file_url" == "null" ]] && continue
    file_count=$((file_count + 1))
    if [[ "$max_files" -gt 0 && "$downloaded" -ge "$max_files" ]]; then
      log "reached max_files=$max_files for $dataset"
      break
    fi

    local base
    base="$(basename "$file_url" | cut -d'?' -f1)"
    local target="$dest_dir/$base"
    if [[ -f "$target" ]]; then
      log "resume skip (exists): $base"
      downloaded=$((downloaded + 1))
      continue
    fi

    log "downloading [$((downloaded + 1))/$file_count]: $base"
    curl -fsSL --retry 3 --retry-delay 5 -o "$target.part" "$file_url"
    mv "$target.part" "$target"
    downloaded=$((downloaded + 1))
    local fsize
    fsize="$(stat -c '%s' "$target" 2>/dev/null || echo 0)"
    bytes_downloaded=$((bytes_downloaded + fsize))
    log "saved $base (${fsize} bytes; session=${bytes_downloaded}, dir=$(du -sb "$dest_dir" 2>/dev/null | awk '{print $1}'))"
  done < <(printf '%s' "$payload" | jq -r '.files[]?')

  if [[ "$file_count" -eq 0 ]]; then
    echo "no files returned for dataset $dataset" >&2
    exit 1
  fi

  {
    echo "dataset=$dataset"
    echo "release=${S2_RELEASE}"
    echo "files_listed=$file_count"
    echo "files_downloaded=$downloaded"
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
