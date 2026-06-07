#!/usr/bin/env bash
# Operator snapshot: warm-index bytes, gate progress, S2 key status.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-runtime-deps.sh
source "$SCRIPT_DIR/install-runtime-deps.sh"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

INGEST_STATE_FILE="${WARM_INDEX_STAGING}/.ingest-run-state.json"

MIN_BYTES="${WARM_INGEST_MIN_BYTES:-1073741824}"

_dir_bytes() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo 0
    return
  fi
  du -sb "$dir" 2>/dev/null | awk '{print $1}' || echo 0
}

s2_bytes() {
  _dir_bytes "${WARM_INDEX_STAGING}/s2"
}

bytes_s2="$(s2_bytes)"
bytes_arxiv="$(_dir_bytes "$ARXIV_OUTPUT_DIR")"
gate_pct=0
if [[ "$MIN_BYTES" -gt 0 ]]; then
  gate_pct=$((bytes_s2 * 100 / MIN_BYTES))
fi

key_status="missing"
reload_s2_api_key && key_status="present"

printf 'warm-index status (%s)\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
printf '  root:        %s\n' "$WARM_INDEX_ROOT"
printf '  staging/s2:  %s bytes (%s%% of %s gate)\n' "$bytes_s2" "$gate_pct" "$MIN_BYTES"
printf '  staging/arxiv: %s bytes\n' "$bytes_arxiv"
printf '  S2_API_KEY:  %s' "$key_status"
[[ -n "${S2_API_KEY_FILE:-}" ]] && printf ' (file=%s)' "$S2_API_KEY_FILE"
printf '\n'

if [[ -f "$INGEST_STATE_FILE" ]]; then
  printf '  state file:  %s\n' "$INGEST_STATE_FILE"
  jq -r '"  gate_passed: \(.gate_passed) | abstracts: \(.datasets.s2_abstracts.status) (\(.datasets.s2_abstracts.files) files)"' \
    "$INGEST_STATE_FILE" 2>/dev/null || true
  jq -r 'if .agent_run_id then "  agent_run_id: \(.agent_run_id)" else empty end' \
    "$INGEST_STATE_FILE" 2>/dev/null || true
fi

if command -v du >/dev/null 2>&1; then
  printf '\nDisk usage:\n'
  du -sh "$WARM_INDEX_STAGING" "$S2_ABSTRACTS_DIR" "$S2_PAPERS_DIR" "$ARXIV_OUTPUT_DIR" 2>/dev/null \
    | sed 's/^/  /' || true
fi

if [[ "$bytes_s2" -lt "$MIN_BYTES" ]]; then
  printf '\nR1b gate: NOT MET (%s / %s bytes)\n' "$bytes_s2" "$MIN_BYTES"
  if [[ "$key_status" == "missing" ]]; then
    printf '  unblock: export S2_API_KEY=... or S2_API_KEY_FILE=/path/to/secret\n'
    printf '           ./scripts/verify-s2-key.sh && ./scripts/run-warm-ingest.sh --resume\n'
  else
    printf '  unblock: ./scripts/run-warm-ingest.sh --resume\n'
  fi
  exit 1
fi

printf '\nR1b gate: MET (%s bytes in staging/s2)\n' "$bytes_s2"
