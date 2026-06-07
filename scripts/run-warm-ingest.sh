#!/usr/bin/env bash
# R1b orchestrator — S2 abstracts → papers → arXiv OAI with resume + state.

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
Usage: run-warm-ingest.sh [--bootstrap] [--resume] [--min-bytes N] [--max-s2-files N] [--wait-for-key SEC]

  --bootstrap       Layout only + bootstrap marker (no downloads)
  --resume          Skip completed phases (default)
  --min-bytes N     Target bytes under staging/s2 before continuing (default: WARM_INGEST_MIN_BYTES or 1 GiB)
  --max-s2-files N  Cap S2 partition downloads per dataset (smoke / partial)
  --wait-for-key SEC  Poll S2_API_KEY / S2_API_KEY_FILE for up to SEC seconds before phase 1

Runs phases in order:
  1. S2 abstracts (priority — loops until min-bytes or release complete)
  2. S2 papers metadata
  3. arXiv CS/ML OAI harvest

Writes staging/.ingest-run-state.json and staging/manifest.json after each phase.
Continues past the min-bytes gate; re-run to resume interrupted downloads.
EOF
}

BOOTSTRAP=0
MAX_S2_FILES=0
WAIT_FOR_KEY_SEC=0
MIN_BYTES="${WARM_INGEST_MIN_BYTES:-1073741824}"

wait_for_s2_key() {
  local max_wait="$1"
  local interval=30
  local elapsed=0

  while [[ "$elapsed" -lt "$max_wait" ]]; do
    reload_s2_api_key && return 0
    log "waiting for S2_API_KEY (${elapsed}/${max_wait}s) — export S2_API_KEY or mount S2_API_KEY_FILE"
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  reload_s2_api_key
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap) BOOTSTRAP=1; shift ;;
    --resume) shift ;;
    --min-bytes)
      MIN_BYTES="${2:?--min-bytes requires a number}"
      shift 2
      ;;
    --max-s2-files)
      MAX_S2_FILES="${2:?--max-s2-files requires a number}"
      shift 2
      ;;
    --wait-for-key)
      WAIT_FOR_KEY_SEC="${2:?--wait-for-key requires seconds}"
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
reload_s2_api_key || true

if [[ "${WARM_INGEST_MODE:-}" == "public" ]] || { [[ -z "${S2_API_KEY:-}" ]] && [[ "${WARM_INGEST_FORCE_S2:-}" != "1" ]]; }; then
  pub_args=()
  [[ "$BOOTSTRAP" -eq 1 ]] && pub_args+=(--bootstrap)
  pub_args+=(--min-bytes "$MIN_BYTES")
  [[ "$MAX_S2_FILES" -gt 0 ]] && pub_args+=(--max-openalex-pages "$MAX_S2_FILES")
  log "public ingest path — run-public-ingest.sh (no S2_API_KEY)"
  exec bash "$SCRIPT_DIR/run-public-ingest.sh" "${pub_args[@]}"
fi

if [[ "$BOOTSTRAP" -eq 1 ]]; then
  write_bootstrap_marker
  write_ingest_run_state
  write_staging_manifest
  exit 0
fi

ensure_staging_tree

if [[ "$WAIT_FOR_KEY_SEC" -gt 0 && -z "${S2_API_KEY:-}" ]]; then
  log "polling for S2_API_KEY up to ${WAIT_FOR_KEY_SEC}s"
  wait_for_s2_key "$WAIT_FOR_KEY_SEC" || log "S2_API_KEY still missing after ${WAIT_FOR_KEY_SEC}s"
fi

run_s2_abstracts_until_gate() {
  local attempt=0
  local max_attempts=3

  while :; do
    attempt=$((attempt + 1))
    local bytes
    bytes="$(s2_bytes)"

    if [[ "$bytes" -ge "$MIN_BYTES" ]]; then
      log "S2 abstracts gate met: ${bytes} >= ${MIN_BYTES} bytes"
      break
    fi

    if [[ -z "${S2_API_KEY:-}" ]]; then
      log "S2_API_KEY not set — cannot download full abstracts corpus"
      log "Obtain a key at https://www.semanticscholar.org/product/api and export S2_API_KEY"
      log "preflight: bash scripts/verify-s2-key.sh"
      if [[ "$attempt" -eq 1 ]]; then
        log "retrying sample path (public ai2-s2ag/samples — well below 1 GiB gate)"
        bash "$SCRIPT_DIR/ingest-s2-abstracts.sh" --samples || true
        write_ingest_run_state
      fi
      break
    fi

    if [[ "$attempt" -eq 1 ]] && ! bash "$SCRIPT_DIR/verify-s2-key.sh" --quiet; then
      log "S2_API_KEY preflight failed — fix key before bulk download"
      break
    fi

    local args=()
    [[ "$MAX_S2_FILES" -gt 0 ]] && args+=(--max-files "$MAX_S2_FILES")

    log "S2 abstracts pass ${attempt}: ${bytes}/${MIN_BYTES} bytes"
    if ! bash "$SCRIPT_DIR/ingest-s2-abstracts.sh" "${args[@]}"; then
      if [[ "$attempt" -ge "$max_attempts" ]]; then
        log "S2 abstracts failed after ${max_attempts} attempts"
        return 1
      fi
      log "S2 abstracts attempt ${attempt} failed — retrying in 30s"
      sleep 30
      continue
    fi

    write_ingest_run_state
    bytes="$(s2_bytes)"
    if [[ "$bytes" -ge "$MIN_BYTES" ]]; then
      break
    fi

    local marker="$S2_ABSTRACTS_DIR/.release-${S2_RELEASE}-abstracts.ok"
    if [[ -f "$marker" ]]; then
      log "S2 abstracts release complete but only ${bytes} bytes (below gate)"
      break
    fi

    if [[ "$MAX_S2_FILES" -gt 0 ]]; then
      log "max-s2-files cap reached with ${bytes} bytes"
      break
    fi
  done
}

log "=== phase 1: S2 abstracts (target >= ${MIN_BYTES} bytes) ==="
run_s2_abstracts_until_gate || true
write_ingest_run_state
write_staging_manifest

log "=== phase 2: S2 papers metadata ==="
if [[ -n "${S2_API_KEY:-}" ]]; then
  papers_args=()
  [[ "$MAX_S2_FILES" -gt 0 ]] && papers_args+=(--max-files "$MAX_S2_FILES")
  bash "$SCRIPT_DIR/ingest-s2-papers.sh" "${papers_args[@]}" || log "S2 papers phase failed (continuing)"
else
  log "skip S2 papers — S2_API_KEY not set"
fi
write_ingest_run_state
write_staging_manifest

log "=== phase 3: arXiv CS/ML OAI ==="
bash "$SCRIPT_DIR/ingest-arxiv-oai.sh" || log "arXiv OAI phase failed (continuing)"
write_ingest_run_state
write_staging_manifest

bytes_final="$(s2_bytes)"
log "warm ingest finished — staging/s2=${bytes_final} bytes (gate=${MIN_BYTES})"
if [[ "$bytes_final" -lt "$MIN_BYTES" ]]; then
  log "R1b gate not met — set S2_API_KEY and re-run: ./scripts/run-warm-ingest.sh --resume"
  exit 2
fi

log "R1b min-bytes gate passed"
