#!/usr/bin/env bash
# CI/local fixture — validate public-index-gate.sh without network or OpenAlex mailto.
# Uses a temp warm-index tree; never touches /warm-index.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=install-runtime-deps.sh
source "$SCRIPT_DIR/install-runtime-deps.sh"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/li-public-index-gate-fixture.XXXXXX")"
MIN_BYTES="${PUBLIC_INDEX_GATE_FIXTURE_MIN_BYTES:-2048}"

cleanup() {
  rm -rf "$FIXTURE_ROOT"
}
trap cleanup EXIT

OPENALEX="$FIXTURE_ROOT/staging/openalex"
ARXIV="$FIXTURE_ROOT/staging/arxiv"
mkdir -p "$OPENALEX" "$ARXIV"

# Synthetic partition files meeting the lowered gate threshold.
dd if=/dev/zero of="$OPENALEX/works-000001.jsonl" bs=1024 count="$((MIN_BYTES / 1024 + 1))" status=none 2>/dev/null
printf '<record/>' >"$ARXIV/cs__cs__LG.xml"

export WARM_INDEX_PATH="$FIXTURE_ROOT"
export WARM_INGEST_MIN_BYTES="$MIN_BYTES"
export WARM_INGEST_MODE=public
export LI_RESEARCH_INGEST_ROOT="$REPO_ROOT"
export PUBLIC_INDEX_GATE_SKIP_BRANCH=1

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
# shellcheck source=lib/ingest-state.sh
source "$SCRIPT_DIR/lib/ingest-state.sh"

write_ingest_run_state
write_staging_manifest

if ! bash "$SCRIPT_DIR/public-index-gate.sh"; then
  echo "test-public-index-gate-fixture: FAIL — gate rejected valid fixture tree" >&2
  exit 1
fi

state_mode="$(jq -r '.ingest_mode' "$FIXTURE_ROOT/staging/.ingest-run-state.json")"
if [[ "$state_mode" != "public" ]]; then
  echo "test-public-index-gate-fixture: FAIL — ingest_mode=${state_mode} (expected public)" >&2
  exit 1
fi

bytes="$(du -sb "$FIXTURE_ROOT/staging/openalex" "$FIXTURE_ROOT/staging/arxiv" 2>/dev/null | awk '{s+=$1} END {print s+0}')"
echo "test-public-index-gate-fixture: OK (${bytes} bytes >= ${MIN_BYTES} public corpus, ingest_mode=public)"
