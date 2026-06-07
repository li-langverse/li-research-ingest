#!/usr/bin/env bash
# Code implementer / supervisor entry — S2 key discovery, warm ingest, gate check, JSON report.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${LI_RESEARCH_INGEST_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=install-runtime-deps.sh
source "$SCRIPT_DIR/install-runtime-deps.sh"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
# shellcheck source=lib/ingest-state.sh
source "$SCRIPT_DIR/lib/ingest-state.sh"

usage() {
  cat <<'EOF'
Usage: agent-r1b-pass.sh [--wait-for-key SEC]

  --wait-for-key SEC  Poll S2_API_KEY before ingest (default: AGENT_R1B_WAIT_KEY_SEC or 0)

Runs discover-s2-key → run-warm-ingest --resume → r1b-gate and prints a JSON summary on stdout.
Exit 0 when r1b-gate passes; 2 when gate not met; 1 on fatal script error.
EOF
}

WAIT_FOR_KEY_SEC="${AGENT_R1B_WAIT_KEY_SEC:-0}"
RUN_ID="${LI_AGENT_RUN_ID:-}"
if [[ -z "$RUN_ID" && -n "${LI_REPO_WORKFLOW_WORKSPACE:-}" ]]; then
  RUN_ID="$(basename "$(dirname "$LI_REPO_WORKFLOW_WORKSPACE")")"
fi
RUN_ID="${RUN_ID:-unknown}"

while [[ $# -gt 0 ]]; do
  case "$1" in
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

export LI_RESEARCH_INGEST_ROOT="$REPO_ROOT"

key_status="missing"
key_source=""
if reload_s2_api_key; then
  key_status="present"
  key_source="${S2_API_KEY_FILE:-env}"
fi

discover_exit=0
bash "$SCRIPT_DIR/discover-s2-key.sh" --quiet >/dev/null 2>&1 || discover_exit=$?
if [[ "$discover_exit" -eq 0 ]]; then
  key_status="present"
  key_source="${S2_API_KEY_FILE:-env}"
fi

ingest_args=(--resume)
[[ "$WAIT_FOR_KEY_SEC" -gt 0 ]] && ingest_args+=(--wait-for-key "$WAIT_FOR_KEY_SEC")

ingest_exit=0
bash "$SCRIPT_DIR/run-warm-ingest.sh" "${ingest_args[@]}" || ingest_exit=$?

bytes_s2="$(s2_bytes)"
min_bytes="${WARM_INGEST_MIN_BYTES:-1073741824}"
gate_passed=false
[[ "$bytes_s2" -ge "$min_bytes" ]] && gate_passed=true

gate_exit=0
bash "$SCRIPT_DIR/r1b-gate.sh" >/dev/null 2>&1 || gate_exit=$?

require_cmd jq
report_json="$(jq -n \
  --arg run_id "$RUN_ID" \
  --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg warm_index_root "$WARM_INDEX_ROOT" \
  --arg key_status "$key_status" \
  --arg key_source "$key_source" \
  --argjson bytes_s2 "$bytes_s2" \
  --argjson min_bytes_gate "$min_bytes" \
  --argjson gate_passed "$gate_passed" \
  --argjson discover_exit "$discover_exit" \
  --argjson ingest_exit "$ingest_exit" \
  --argjson gate_exit "$gate_exit" \
  '{
    agent_run_id: $run_id,
    updated_at: $updated_at,
    warm_index_root: $warm_index_root,
    s2_api_key: { status: $key_status, source: $key_source },
    bytes: { s2: $bytes_s2, min_bytes_gate: $min_bytes_gate },
    gate_passed: $gate_passed,
    exits: { discover: $discover_exit, ingest: $ingest_exit, gate: $gate_exit }
  }')"

printf '%s\n' "$report_json"

agent_report_file="${WARM_INDEX_STAGING}/.agent-r1b-report.json"
if printf '%s\n' "$report_json" >"$agent_report_file" 2>/dev/null; then
  log "agent report: $agent_report_file"
fi

if [[ "$gate_exit" -eq 0 ]]; then
  exit 0
fi
if [[ "$gate_passed" == false ]]; then
  exit 2
fi
exit 1
