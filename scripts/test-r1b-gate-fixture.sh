#!/usr/bin/env bash
# CI/local fixture — validate r1b-gate.sh byte + file checks without S2_API_KEY or network.
# Uses a temp warm-index tree; never touches /warm-index.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/li-r1b-gate-fixture.XXXXXX")"
MIN_BYTES="${R1B_GATE_FIXTURE_MIN_BYTES:-2048}"

cleanup() {
  rm -rf "$FIXTURE_ROOT"
}
trap cleanup EXIT

ABSTRACTS="$FIXTURE_ROOT/staging/s2/abstracts"
mkdir -p "$ABSTRACTS"

# One partition file meeting the lowered gate threshold (not real S2 corpus).
dd if=/dev/zero of="$ABSTRACTS/partition-000.jsonl.gz" bs=1024 count="$((MIN_BYTES / 1024 + 1))" status=none 2>/dev/null

export WARM_INDEX_PATH="$FIXTURE_ROOT"
export WARM_INGEST_MIN_BYTES="$MIN_BYTES"
export LI_RESEARCH_INGEST_ROOT="$REPO_ROOT"
# PR merge checkouts in CI are detached HEAD — skip branch ref probe.
export R1B_GATE_SKIP_BRANCH=1

# Shallow PR checkouts may not fetch origin/cursor/li-research-r1b; gate checks that ref.
if ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/cursor/li-research-r1b" \
  && ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/cursor/li-research-r1b"; then
  git -C "$REPO_ROOT" branch -f cursor/li-research-r1b HEAD
fi

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
# shellcheck source=lib/ingest-state.sh
source "$SCRIPT_DIR/lib/ingest-state.sh"

write_ingest_run_state
write_staging_manifest

if ! bash "$SCRIPT_DIR/r1b-gate.sh"; then
  echo "test-r1b-gate-fixture: FAIL — gate rejected valid fixture tree" >&2
  exit 1
fi

bytes="$(du -sb "$FIXTURE_ROOT/staging/s2" | awk '{print $1}')"
echo "test-r1b-gate-fixture: OK (${bytes} bytes >= ${MIN_BYTES} in temp staging/s2)"
