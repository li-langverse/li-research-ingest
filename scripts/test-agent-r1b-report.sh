#!/usr/bin/env bash
# CI/local fixture — validate agent-r1b-pass.sh JSON schema without S2_API_KEY or network.
# Uses a temp warm-index tree; never touches /warm-index.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=install-runtime-deps.sh
source "$SCRIPT_DIR/install-runtime-deps.sh"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/li-r1b-agent-report.XXXXXX")"

cleanup() {
  rm -rf "$FIXTURE_ROOT"
}
trap cleanup EXIT

ABSTRACTS="$FIXTURE_ROOT/staging/s2/abstracts"
mkdir -p "$ABSTRACTS"
printf '%s\n' '{"sample":true}' | gzip >"$ABSTRACTS/abstracts-sample.jsonl.gz"

# Skip arXiv OAI network harvest — mark all configured sets complete.
ARXIV_DIR="$FIXTURE_ROOT/staging/arxiv"
mkdir -p "$ARXIV_DIR"
for set_spec in cs:cs:AI cs:cs:LG cs:cs:CL stat:stat:ML; do
  safe_name="$(printf '%s' "$set_spec" | tr ':/' '__')"
  printf 'set=%s\nrecords=0\ncompleted_at=fixture\n' "$set_spec" >"$ARXIV_DIR/.${safe_name}.ok"
done

export WARM_INDEX_PATH="$FIXTURE_ROOT"
export WARM_INGEST_MIN_BYTES=1073741824
export LI_RESEARCH_INGEST_ROOT="$REPO_ROOT"
export LI_AGENT_RUN_ID=test-agent-r1b-report
export R1B_GATE_SKIP_BRANCH=1
# Supervisor sets LI_GOAL_SELF_UNBLOCK=1 globally; fixture must not poll 300s for S2 key.
unset LI_GOAL_SELF_UNBLOCK AGENT_R1B_WAIT_KEY_SEC UNBLOCK_R1B_WAIT_KEY_SEC

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
# shellcheck source=lib/ingest-state.sh
source "$SCRIPT_DIR/lib/ingest-state.sh"

write_ingest_run_state
write_staging_manifest

report_file="$(mktemp "${TMPDIR:-/tmp}/li-r1b-report.XXXXXX")"
set +e
bash "$SCRIPT_DIR/agent-r1b-pass.sh" >"$report_file" 2>/dev/null
agent_exit=$?
set -e

if [[ "$agent_exit" -ne 2 ]]; then
  echo "test-agent-r1b-report: FAIL — expected exit 2 (gate not met), got ${agent_exit}" >&2
  cat "$report_file" >&2 || true
  exit 1
fi

require_cmd jq

jq -e '
  .agent_run_id == "test-agent-r1b-report"
  and (.gate_passed | type) == "boolean"
  and .gate_passed == false
  and (.bytes.s2 | type) == "number"
  and (.bytes.arxiv | type) == "number"
  and (.bytes.total | type) == "number"
  and (.bytes.min_bytes_gate | type) == "number"
  and (.warm_secrets_dropin.writable | type) == "boolean"
  and (.li_secrets_dir.exists | type) == "boolean"
  and (.li_secrets_dir.writable | type) == "boolean"
  and (.li_secrets_dir.has_s2_key | type) == "boolean"
  and (.s2_api_key.status | type) == "string"
  and (.s2_api_key.configured_file | type) == "string" or .s2_api_key.configured_file == null
  and (.s2_api_key.configured_file_empty | type) == "boolean"
  and (.s2_api_key.probed_paths | type) == "number"
  and (.s2_api_key.probed_paths >= 1)
  and (.s2_api_key.empty_dir_mounts | type) == "number"
  and (.s2_api_key.empty_dir_mounts >= 0)
  and (.phase_checklist.branch == "done")
  and (.phase_checklist.runner == "done")
  and (.phase_checklist.s2_abstracts | IN("blocked", "in_progress", "done", "pending"))
  and (.phase_checklist.state | IN("done", "pending"))
  and (.phase_checklist.manifest | IN("done", "pending"))
  and (.phase_checklist.runbook == "done")
  and (.exits.discover | type) == "number"
  and (.exits.ingest | type) == "number"
  and (.exits.gate | type) == "number"
  and (.north_star_fit | type) == "string"
  and (.warm_index_disk.avail_bytes | type) == "number"
' "$report_file" >/dev/null || {
  echo "test-agent-r1b-report: FAIL — JSON schema validation failed" >&2
  cat "$report_file" >&2
  exit 1
}

if [[ ! -f "$FIXTURE_ROOT/staging/.agent-r1b-report.json" ]]; then
  echo "test-agent-r1b-report: FAIL — missing persisted .agent-r1b-report.json" >&2
  exit 1
fi

echo "test-agent-r1b-report: OK (exit=${agent_exit}, schema valid)"
