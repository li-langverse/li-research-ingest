#!/usr/bin/env bash
# Public-API orchestrator — arXiv OAI + OpenAlex REST (no S2 API key).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-runtime-deps.sh
source "$SCRIPT_DIR/install-runtime-deps.sh"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
# shellcheck source=lib/ingest-state.sh
source "$SCRIPT_DIR/lib/ingest-state.sh"

usage() {
  cat <<'EOF'
Usage: run-public-ingest.sh [--bootstrap] [--resume] [--min-bytes N] [--max-openalex-pages N]

  --bootstrap           Layout only
  --resume              Skip completed phases (default)
  --min-bytes N         Gate target for openalex+arxiv bytes (default 100 MiB)
  --max-openalex-pages  Cap OpenAlex API pages per run (smoke)

No S2_API_KEY required. Set OPENALEX_MAILTO for polite pool.
EOF
}

BOOTSTRAP=0
MAX_OPENALEX_PAGES=0
MIN_BYTES="${WARM_INGEST_MIN_BYTES:-104857600}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap) BOOTSTRAP=1; shift ;;
    --resume) shift ;;
    --min-bytes)
      MIN_BYTES="${2:?--min-bytes requires a number}"
      shift 2
      ;;
    --max-openalex-pages)
      MAX_OPENALEX_PAGES="${2:?--max-openalex-pages requires a number}"
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

export WARM_INGEST_MIN_BYTES="$MIN_BYTES"
export WARM_INGEST_MODE=public

if [[ "$BOOTSTRAP" -eq 1 ]]; then
  ensure_staging_tree
  mkdir -p "$OPENALEX_OUTPUT_DIR"
  write_bootstrap_marker
  bash "$SCRIPT_DIR/ingest-openalex.sh" --bootstrap
  bash "$SCRIPT_DIR/ingest-arxiv-oai.sh" --bootstrap
  write_ingest_run_state
  write_staging_manifest
  exit 0
fi

ensure_staging_tree
mkdir -p "$OPENALEX_OUTPUT_DIR"

if [[ -z "${OPENALEX_MAILTO:-}" ]]; then
  export OPENALEX_MAILTO="${LI_OPENALEX_MAILTO:-li-research-ingest@li-langverse.dev}"
  log "OPENALEX_MAILTO defaulted to ${OPENALEX_MAILTO}"
fi

log "=== public ingest phase 1: arXiv CS/ML OAI ==="
bash "$SCRIPT_DIR/ingest-arxiv-oai.sh" || log "arXiv OAI phase failed (continuing)"
write_ingest_run_state
write_staging_manifest

log "=== public ingest phase 2: OpenAlex works (field=CS) ==="
oa_args=()
[[ "$MAX_OPENALEX_PAGES" -gt 0 ]] && oa_args+=(--max-pages "$MAX_OPENALEX_PAGES")

run_openalex_until_gate() {
  local attempt=0
  while :; do
    attempt=$((attempt + 1))
    bytes_public="$(public_index_bytes)"
    if [[ "$bytes_public" -ge "$MIN_BYTES" ]]; then
      log "public index gate met: ${bytes_public} >= ${MIN_BYTES}"
      return 0
    fi
    log "OpenAlex pass ${attempt}: ${bytes_public}/${MIN_BYTES} bytes (public)"
    if ! bash "$SCRIPT_DIR/ingest-openalex.sh" --resume "${oa_args[@]}"; then
      log "OpenAlex ingest failed on pass ${attempt}"
      return 1
    fi
    write_ingest_run_state
    write_staging_manifest
    bytes_public="$(public_index_bytes)"
    if [[ "$bytes_public" -ge "$MIN_BYTES" ]]; then
      return 0
    fi
    if [[ -f "$OPENALEX_OUTPUT_DIR/.openalex-harvest-complete.ok" ]]; then
      log "OpenAlex complete but only ${bytes_public} bytes (below gate)"
      return 0
    fi
    if [[ "$MAX_OPENALEX_PAGES" -gt 0 ]]; then
      log "max-openalex-pages reached with ${bytes_public} bytes"
      return 0
    fi
    sleep "${OPENALEX_REQUEST_INTERVAL_SEC:-1}"
  done
}

run_openalex_until_gate || true
write_ingest_run_state
write_staging_manifest

bytes_final="$(public_index_bytes)"
log "public ingest finished — openalex+arxiv=${bytes_final} bytes (gate=${MIN_BYTES})"
if [[ "$bytes_final" -lt "$MIN_BYTES" ]]; then
  exit 2
fi

log "public index min-bytes gate passed"
