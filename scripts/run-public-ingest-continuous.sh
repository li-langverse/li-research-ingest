#!/usr/bin/env bash
# Week-long daemon — full arXiv OAI first, then OpenAlex until complete.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-runtime-deps.sh
source "$SCRIPT_DIR/install-runtime-deps.sh"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
# shellcheck source=lib/oai-xml.sh
source "$SCRIPT_DIR/lib/oai-xml.sh"
# shellcheck source=lib/ingest-state.sh
source "$SCRIPT_DIR/lib/ingest-state.sh"

LOOP_SLEEP="${PUBLIC_INGEST_LOOP_SLEEP_SEC:-60}"

export WARM_INGEST_MODE=public
export WARM_INGEST_MIN_BYTES="${WARM_INGEST_MIN_BYTES:-104857600}"

if [[ -z "${OPENALEX_MAILTO:-}" ]]; then
  export OPENALEX_MAILTO="${LI_OPENALEX_MAILTO:-li-research-ingest@li-langverse.dev}"
fi

ensure_staging_tree
mkdir -p "$OPENALEX_OUTPUT_DIR" "$ARXIV_FULL_OUTPUT_DIR"

log "continuous public ingest started (arxiv_full=${ARXIV_FULL_CORPUS:-0}, loop_sleep=${LOOP_SLEEP}s)"

while true; do
  if [[ "${ARXIV_FULL_CORPUS:-0}" == "1" ]] && ! arxiv_full_harvest_complete; then
    log "continuous: arXiv FULL corpus harvest (3s/request — may run for days)"
    if bash "$SCRIPT_DIR/ingest-arxiv-oai.sh"; then
      write_ingest_run_state
      write_staging_manifest
    else
      log "continuous: arXiv full harvest error — backoff ${LOOP_SLEEP}s"
      sleep "$LOOP_SLEEP"
    fi
    continue
  fi

  if [[ -f "$OPENALEX_OUTPUT_DIR/.openalex-harvest-complete.ok" ]]; then
    log "continuous: arXiv + OpenAlex complete — idle ${LOOP_SLEEP}s"
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
