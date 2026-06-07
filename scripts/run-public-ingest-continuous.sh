#!/usr/bin/env bash
# Week-long daemon — arXiv refresh + OpenAlex pagination until corpus complete.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-runtime-deps.sh
source "$SCRIPT_DIR/install-runtime-deps.sh"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
# shellcheck source=lib/ingest-state.sh
source "$SCRIPT_DIR/lib/ingest-state.sh"

LOOP_SLEEP="${PUBLIC_INGEST_LOOP_SLEEP_SEC:-60}"
ARXIV_REFRESH_HOURS="${ARXIV_REFRESH_INTERVAL_HOURS:-24}"

export WARM_INGEST_MODE=public
export WARM_INGEST_MIN_BYTES="${WARM_INGEST_MIN_BYTES:-104857600}"

if [[ -z "${OPENALEX_MAILTO:-}" ]]; then
  export OPENALEX_MAILTO="${LI_OPENALEX_MAILTO:-li-research-ingest@li-langverse.dev}"
fi

ensure_staging_tree
mkdir -p "$OPENALEX_OUTPUT_DIR"

last_arxiv_refresh=0

maybe_refresh_arxiv() {
  local now epoch_refresh
  now="$(date +%s)"
  epoch_refresh=$((ARXIV_REFRESH_HOURS * 3600))
  if [[ "$last_arxiv_refresh" -eq 0 ]] || (( now - last_arxiv_refresh >= epoch_refresh )); then
    log "continuous: arXiv OAI refresh"
    bash "$SCRIPT_DIR/ingest-arxiv-oai.sh" || log "arXiv refresh failed (continuing)"
    last_arxiv_refresh="$now"
    write_ingest_run_state
    write_staging_manifest
  fi
}

log "continuous public ingest started (loop_sleep=${LOOP_SLEEP}s, arxiv_refresh=${ARXIV_REFRESH_HOURS}h)"

while true; do
  maybe_refresh_arxiv

  if [[ -f "$OPENALEX_OUTPUT_DIR/.openalex-harvest-complete.ok" ]]; then
    log "continuous: OpenAlex harvest complete — idle ${LOOP_SLEEP}s"
    write_ingest_run_state
    sleep "$LOOP_SLEEP"
    continue
  fi

  bytes_public="$(public_index_bytes)"
  log "continuous: OpenAlex pass — corpus=${bytes_public} bytes"
  if bash "$SCRIPT_DIR/ingest-openalex.sh" --resume; then
    write_ingest_run_state
    write_staging_manifest
  else
    log "continuous: OpenAlex pass failed — backoff ${LOOP_SLEEP}s"
    sleep "$LOOP_SLEEP"
    continue
  fi

  sleep "${OPENALEX_REQUEST_INTERVAL_SEC:-1}"
done
