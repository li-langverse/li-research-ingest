#!/usr/bin/env bash
# R1b gate loop — poll S2_API_KEY, run warm ingest, retry until gate passes.
# For engine pod supervisors (LI_GOAL_LOOP_SLEEP_SEC) waiting on Vault wiring.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${LI_RESEARCH_INGEST_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

usage() {
  cat <<'EOF'
Usage: gate-loop.sh [--once] [--wait-for-key SEC] [--sleep SEC] [--max-iter N]

  --once            Single ingest pass + gate check (no retry loop)
  --wait-for-key SEC  Poll S2_API_KEY before each ingest (default: GATE_LOOP_WAIT_KEY_SEC or 300)
  --sleep SEC       Seconds between retries (default: LI_GOAL_LOOP_SLEEP_SEC or 300)
  --max-iter N      Stop after N iterations (default: GATE_LOOP_MAX_ITER or 0 = unlimited)

Runs run-warm-ingest.sh then r1b-gate.sh until the ≥1 GiB staging/s2 gate passes.
Exits 0 on gate OK, 2 when max iterations reached without gate, 1 on fatal error.
EOF
}

ONCE=0
WAIT_FOR_KEY_SEC="${GATE_LOOP_WAIT_KEY_SEC:-300}"
SLEEP_SEC="${LI_GOAL_LOOP_SLEEP_SEC:-300}"
MAX_ITER="${GATE_LOOP_MAX_ITER:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) ONCE=1; shift ;;
    --wait-for-key)
      WAIT_FOR_KEY_SEC="${2:?--wait-for-key requires seconds}"
      shift 2
      ;;
    --sleep)
      SLEEP_SEC="${2:?--sleep requires seconds}"
      shift 2
      ;;
    --max-iter)
      MAX_ITER="${2:?--max-iter requires a number}"
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

export LI_RESEARCH_INGEST_ROOT="$REPO_ROOT"
export WARM_INGEST_MIN_BYTES="${WARM_INGEST_MIN_BYTES:-1073741824}"

run_ingest_pass() {
  bash "$SCRIPT_DIR/run-warm-ingest.sh" \
    --wait-for-key "$WAIT_FOR_KEY_SEC" \
    --resume \
    || true
}

iter=0
while :; do
  iter=$((iter + 1))
  log "gate-loop iteration ${iter} (wait-for-key=${WAIT_FOR_KEY_SEC}s)"

  run_ingest_pass

  if bash "$SCRIPT_DIR/r1b-gate.sh"; then
    log "gate-loop: R1b gate OK"
    exit 0
  fi

  if [[ "$ONCE" -eq 1 ]]; then
    log "gate-loop: --once complete, gate not met"
    exit 2
  fi

  if [[ "$MAX_ITER" -gt 0 && "$iter" -ge "$MAX_ITER" ]]; then
    log "gate-loop: max iterations (${MAX_ITER}) reached without gate"
    exit 2
  fi

  log "gate-loop: sleeping ${SLEEP_SEC}s (set S2_API_KEY or mount S2_API_KEY_FILE to unblock)"
  sleep "$SLEEP_SEC"
done
