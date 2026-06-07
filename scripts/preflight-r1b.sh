#!/usr/bin/env bash
# R1b operator preflight — S2 key discovery, warm-index status, completion gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failures=0

run_step() {
  local label="$1"
  shift
  printf '\n=== %s ===\n' "$label"
  "$@"
  local code=$?
  if [[ "$code" -eq 0 ]]; then
    return 0
  fi
  failures=$((failures + 1))
  printf '=== %s: FAILED (exit %s) ===\n' "$label" "$code"
  return 0
}

set +e
run_step "S2 key discovery" bash "$SCRIPT_DIR/discover-s2-key.sh"
run_step "warm-index status" bash "$SCRIPT_DIR/status-warm-index.sh"
run_step "R1b completion gate" bash "$SCRIPT_DIR/r1b-gate.sh"
set -e

if [[ "$failures" -eq 0 ]]; then
  printf '\nR1b preflight: OK\n'
  exit 0
fi

printf '\nR1b preflight: %s check(s) failed — see output above\n' "$failures"
printf 'Unblock: export S2_API_KEY=... or mount at S2_API_KEY_FILE / LI_SECRETS_DIR/s2-api-key\n'
printf '         ./scripts/verify-s2-key.sh && ./scripts/run-warm-ingest.sh --resume\n'
exit 1
