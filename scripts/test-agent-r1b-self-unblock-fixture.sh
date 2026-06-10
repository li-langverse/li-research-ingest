#!/usr/bin/env bash
# CI/local fixture — agent-r1b-pass honors LI_GOAL_SELF_UNBLOCK wait-for-key default.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=install-runtime-deps.sh
source "$SCRIPT_DIR/install-runtime-deps.sh"

FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/li-r1b-self-unblock.XXXXXX")"
cleanup() { rm -rf "$FIXTURE_ROOT"; }
trap cleanup EXIT

ABSTRACTS="$FIXTURE_ROOT/staging/s2/abstracts"
mkdir -p "$ABSTRACTS"
printf '%s\n' '{"sample":true}' | gzip >"$ABSTRACTS/abstracts-sample.jsonl.gz"

export WARM_INDEX_PATH="$FIXTURE_ROOT"
export WARM_INGEST_MIN_BYTES=1073741824
export LI_RESEARCH_INGEST_ROOT="$REPO_ROOT"
export LI_AGENT_RUN_ID=test-agent-r1b-self-unblock
export R1B_GATE_SKIP_BRANCH=1
export LI_GOAL_SELF_UNBLOCK=1
export LI_GOAL_LOOP_SLEEP_SEC=2
export AGENT_R1B_WAIT_KEY_SEC=0
unset S2_API_KEY S2_API_KEY_FILE UNBLOCK_R1B_WAIT_KEY_SEC

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
# shellcheck source=lib/ingest-state.sh
source "$SCRIPT_DIR/lib/ingest-state.sh"
write_ingest_run_state

log_file="$(mktemp "${TMPDIR:-/tmp}/li-r1b-self-unblock-log.XXXXXX")"
start_ts="$(date +%s)"
set +e
bash "$SCRIPT_DIR/agent-r1b-pass.sh" >"$log_file" 2>&1
agent_exit=$?
set -e
elapsed=$(( $(date +%s) - start_ts ))

if [[ "$agent_exit" -ne 2 ]]; then
  echo "test-agent-r1b-self-unblock-fixture: FAIL — expected exit 2, got ${agent_exit}" >&2
  cat "$log_file" >&2
  exit 1
fi

if ! grep -q 'self-unblock: polling for S2_API_KEY up to 2s' "$log_file"; then
  echo "test-agent-r1b-self-unblock-fixture: FAIL — missing self-unblock wait log" >&2
  cat "$log_file" >&2
  exit 1
fi

if [[ "$elapsed" -lt 2 ]]; then
  echo "test-agent-r1b-self-unblock-fixture: FAIL — expected >=2s wait, elapsed=${elapsed}s" >&2
  exit 1
fi

echo "test-agent-r1b-self-unblock-fixture: OK (exit=${agent_exit}, elapsed=${elapsed}s)"
