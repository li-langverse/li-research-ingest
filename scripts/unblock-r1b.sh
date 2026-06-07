#!/usr/bin/env bash
# Operator entry — poll S2_API_KEY, run warm ingest, retry until R1b ≥1 GiB gate passes.
# Wraps gate-loop.sh with R1b defaults (see README / issue #6 for Vault wiring).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: unblock-r1b.sh [--once] [--wait-for-key SEC] [--sleep SEC]

  --once            Single ingest pass + gate check (no retry loop)
  --wait-for-key SEC  Poll S2_API_KEY before ingest (default: 3600)
  --sleep SEC       Seconds between retries (default: LI_GOAL_LOOP_SLEEP_SEC or 300)

Runs discover-s2-key → gate-loop until staging/s2 ≥ WARM_INGEST_MIN_BYTES (1 GiB).
Exits 0 when r1b-gate.sh passes; 2 when gate not met after --once or max iterations.
EOF
}

WAIT_FOR_KEY_SEC="${UNBLOCK_R1B_WAIT_KEY_SEC:-3600}"
SLEEP_SEC="${LI_GOAL_LOOP_SLEEP_SEC:-300}"
EXTRA=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) EXTRA+=(--once); shift ;;
    --wait-for-key)
      WAIT_FOR_KEY_SEC="${2:?--wait-for-key requires seconds}"
      shift 2
      ;;
    --sleep)
      SLEEP_SEC="${2:?--sleep requires seconds}"
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

printf '=== R1b unblock (S2 key → warm ingest → gate) ===\n'
bash "$SCRIPT_DIR/discover-s2-key.sh" || true

exec bash "$SCRIPT_DIR/gate-loop.sh" \
  --wait-for-key "$WAIT_FOR_KEY_SEC" \
  --sleep "$SLEEP_SEC" \
  "${EXTRA[@]}"
