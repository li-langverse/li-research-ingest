#!/usr/bin/env bash
# Phase 3 — arXiv CS/ML OAI metadata → /warm-index/staging/arxiv

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

usage() {
  cat <<'EOF'
Usage: ingest-arxiv-oai.sh [--bootstrap] [--set SPEC] [--max-records N]

  --bootstrap     Create staging tree + empty harvest manifest
  --set SPEC      OAI setSpec (default: all CS/ML sets from config)
  --max-records   Stop after N records per set (smoke / partial ingest)
EOF
}

BOOTSTRAP=0
MAX_RECORDS=0
SET_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap) BOOTSTRAP=1; shift ;;
    --set)
      SET_OVERRIDE="${2:?--set requires a value}"
      shift 2
      ;;
    --max-records)
      MAX_RECORDS="${2:?--max-records requires a number}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

ensure_staging_tree

if [[ "$BOOTSTRAP" -eq 1 ]]; then
  write_bootstrap_marker
  : >"$ARXIV_OUTPUT_DIR/.harvest-manifest.tsv"
  log "bootstrap: arxiv staging at $ARXIV_OUTPUT_DIR"
  exit 0
fi

require_cmd curl
require_cmd xmllint

mapfile -t ARXIV_SETS < <(toml_array_values arxiv sets)
if [[ -n "$SET_OVERRIDE" ]]; then
  ARXIV_SETS=("$SET_OVERRIDE")
fi

if [[ "${#ARXIV_SETS[@]}" -eq 0 ]]; then
  echo "no arXiv OAI sets configured" >&2
  exit 1
fi

harvest_set() {
  local set_spec="$1"
  local safe_name
  safe_name="$(printf '%s' "$set_spec" | tr ':/' '__')"
  local out_file="$ARXIV_OUTPUT_DIR/${safe_name}.xml"
  local marker="$ARXIV_OUTPUT_DIR/.${safe_name}.ok"

  if [[ -f "$marker" ]]; then
    log "skip arXiv set $set_spec — marker present"
    return 0
  fi

  local token=""
  local page=0
  local total_records=0
  : >"$out_file.part"

  while :; do
    page=$((page + 1))
    local query="${ARXIV_OAI_ENDPOINT}?verb=ListRecords&metadataPrefix=${ARXIV_METADATA_PREFIX}&set=${set_spec}"
    if [[ -n "$token" ]]; then
      query="${ARXIV_OAI_ENDPOINT}?verb=ListRecords&resumptionToken=${token}"
    fi

    log "arXiv OAI page $page set=$set_spec"
    local tmp
    tmp="$(mktemp)"
    curl -fsSL --retry 3 --retry-delay 5 -o "$tmp" "$query"

    local page_records=0
    page_records="$(xmllint --xpath 'count(//*[local-name()="record"])' "$tmp" 2>/dev/null || echo 0)"
    page_records=$((page_records + 0))
    if [[ "$page_records" -gt 0 ]]; then
      xmllint --xpath '//*[local-name()="ListRecords"]/*[local-name()="record"]' "$tmp" >>"$out_file.part" 2>/dev/null || cat "$tmp" >>"$out_file.part"
      total_records=$((total_records + page_records))
    fi

    token="$(xmllint --xpath 'string(//*[local-name()="resumptionToken")' "$tmp" 2>/dev/null || true)"
    rm -f "$tmp"

    if [[ "$MAX_RECORDS" -gt 0 && "$total_records" -ge "$MAX_RECORDS" ]]; then
      log "reached max-records=$MAX_RECORDS for set=$set_spec"
      break
    fi

    if [[ -z "$token" || "$token" == "null" ]]; then
      break
    fi

    sleep "$ARXIV_REQUEST_INTERVAL"
  done

  mv "$out_file.part" "$out_file"
  {
    echo "set=$set_spec"
    echo "records=$total_records"
    echo "completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } >"$marker"
  log "finished arXiv set $set_spec → $out_file"
}

for set_spec in "${ARXIV_SETS[@]}"; do
  set_spec="$(printf '%s' "$set_spec" | xargs)"
  [[ -z "$set_spec" ]] && continue
  harvest_set "$set_spec"
  sleep "$ARXIV_REQUEST_INTERVAL"
done

printf 'set\tfile\tcompleted\n' >"$ARXIV_OUTPUT_DIR/.harvest-manifest.tsv"
for set_spec in "${ARXIV_SETS[@]}"; do
  set_spec="$(printf '%s' "$set_spec" | xargs)"
  [[ -z "$set_spec" ]] && continue
  safe_name="$(printf '%s' "$set_spec" | tr ':/' '__')"
  printf '%s\t%s\n' "$set_spec" "$ARXIV_OUTPUT_DIR/${safe_name}.xml" >>"$ARXIV_OUTPUT_DIR/.harvest-manifest.tsv"
done
