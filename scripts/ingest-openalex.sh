#!/usr/bin/env bash
# Phase — OpenAlex works (public REST) → /warm-index/staging/openalex

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-runtime-deps.sh
source "$SCRIPT_DIR/install-runtime-deps.sh"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
# shellcheck source=lib/openalex-fetch.sh
source "$SCRIPT_DIR/lib/openalex-fetch.sh"

usage() {
  cat <<'EOF'
Usage: ingest-openalex.sh [--bootstrap] [--resume] [--max-pages N]

  --bootstrap   Create staging tree + empty cursor state
  --resume      Continue from saved cursor (default)
  --max-pages   Stop after N API pages (smoke / partial)

Requires OPENALEX_MAILTO (polite pool). No API key.
EOF
}

BOOTSTRAP=0
MAX_PAGES=0
RESUME=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap) BOOTSTRAP=1; shift ;;
    --resume) RESUME=1; shift ;;
    --no-resume) RESUME=0; shift ;;
    --max-pages)
      MAX_PAGES="${2:?--max-pages requires a number}"
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
mkdir -p "$OPENALEX_OUTPUT_DIR"

CURSOR_STATE="$OPENALEX_OUTPUT_DIR/.cursor-state.json"
COMPLETE_MARKER="$OPENALEX_OUTPUT_DIR/.openalex-harvest-complete.ok"

if [[ "$BOOTSTRAP" -eq 1 ]]; then
  write_bootstrap_marker
  echo '{"cursor":"*","pages":0}' >"$CURSOR_STATE"
  log "bootstrap: openalex staging at $OPENALEX_OUTPUT_DIR"
  exit 0
fi

if [[ -f "$COMPLETE_MARKER" ]]; then
  log "skip OpenAlex — harvest complete marker present"
  exit 0
fi

require_cmd curl
require_cmd jq

: "${OPENALEX_MAILTO:?OPENALEX_MAILTO required — e.g. export OPENALEX_MAILTO=you@example.com}"

interval="${OPENALEX_REQUEST_INTERVAL_SEC:-1}"
cursor="*"
pages_done=0

if [[ "$RESUME" -eq 1 && -f "$CURSOR_STATE" ]]; then
  cursor="$(jq -r '.cursor // "*"' "$CURSOR_STATE")"
  pages_done="$(jq -r '.pages // 0' "$CURSOR_STATE")"
  [[ "$cursor" == "null" || -z "$cursor" ]] && cursor="*"
fi

page_num="$pages_done"
tmp_json="$(mktemp "${TMPDIR:-/tmp}/openalex-page.XXXXXX.json")"
trap 'rm -f "$tmp_json" "$tmp_json.part"' EXIT

while :; do
  if [[ "$MAX_PAGES" -gt 0 && "$page_num" -ge $((pages_done + MAX_PAGES)) ]]; then
    log "reached max-pages=${MAX_PAGES}"
    break
  fi

  page_num=$((page_num + 1))
  part_file="$OPENALEX_OUTPUT_DIR/works-$(printf '%06d' "$page_num").jsonl"
  if [[ -f "$part_file" ]]; then
    log "resume skip page ${page_num} (exists)"
    next_cursor="$(jq -r '.next_cursor // empty' "$CURSOR_STATE" 2>/dev/null || true)"
    if [[ -n "$next_cursor" && "$next_cursor" != "null" ]]; then
      cursor="$next_cursor"
      pages_done="$page_num"
      sleep "$interval"
      continue
    fi
  fi

  log "OpenAlex page ${page_num} cursor=${cursor}"
  if ! openalex_fetch_page "$cursor" "$tmp_json"; then
    exit 1
  fi

  : >"$part_file"
  openalex_results_to_jsonl "$tmp_json" "$part_file"

  local_count="$(wc -l <"$part_file" | tr -d ' ')"
  next_cursor="$(jq -r '.meta.next_cursor // empty' "$tmp_json")"

  jq -n \
    --arg cursor "$cursor" \
    --arg next_cursor "$next_cursor" \
    --arg last_page_file "$part_file" \
    --argjson pages "$page_num" \
    --argjson records "$local_count" \
    --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      cursor: $cursor,
      next_cursor: (if $next_cursor == "" then null else $next_cursor end),
      last_page_file: $last_page_file,
      pages: $pages,
      last_page_records: $records,
      updated_at: $updated_at
    }' >"$CURSOR_STATE"

  pages_done="$page_num"
  log "saved ${part_file} (${local_count} works)"

  if [[ -z "$next_cursor" || "$next_cursor" == "null" ]]; then
    date -u +"%Y-%m-%dT%H:%M:%SZ" >"$COMPLETE_MARKER"
    log "OpenAlex harvest complete (${page_num} pages)"
    break
  fi

  cursor="$next_cursor"
  sleep "$interval"
done

log "OpenAlex ingest stopped at page ${page_num}"
