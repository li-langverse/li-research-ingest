#!/usr/bin/env bash
# Syntax-check ingest shell scripts (no network).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

shopt -s globstar nullglob
scripts=(
  "$SCRIPT_DIR"/*.sh
  "$SCRIPT_DIR"/lib/*.sh
)

for f in "${scripts[@]}"; do
  bash -n "$f"
done

test -f "$REPO_ROOT/config/datasets.toml"
test -f "$REPO_ROOT/scripts/run-warm-ingest.sh"
test -f "$REPO_ROOT/scripts/ingest-all.sh"
test -f "$REPO_ROOT/scripts/r1b-gate.sh"
test -f "$REPO_ROOT/scripts/test-r1b-gate-fixture.sh"
test -f "$REPO_ROOT/scripts/test-agent-r1b-report.sh"
test -f "$REPO_ROOT/scripts/run-public-ingest.sh"
test -f "$REPO_ROOT/scripts/public-index-gate.sh"
test -f "$REPO_ROOT/scripts/test-public-index-gate-fixture.sh"

echo "shell-check: OK (${#scripts[@]} scripts)"
