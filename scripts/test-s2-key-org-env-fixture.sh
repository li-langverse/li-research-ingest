#!/usr/bin/env bash
# CI/local fixture — reload_s2_api_key reads S2_API_KEY from org-level li/.env.github.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/li-s2-key-org.XXXXXX")"
FIXTURE_REPO="${FIXTURE_ROOT}/li-research-ingest/agent-run/repo"

cleanup() {
  rm -rf "$FIXTURE_ROOT"
  unset S2_API_KEY S2_API_KEY_FILE LI_REPO_WORKFLOW_WORKSPACE LI_GITHUB_ENV
}
trap cleanup EXIT

mkdir -p "$FIXTURE_REPO" "${FIXTURE_ROOT}/li"
printf 'S2_API_KEY=test-key-from-org-li-env\n' >"${FIXTURE_ROOT}/li/.env.github"

unset S2_API_KEY S2_API_KEY_FILE LI_GITHUB_ENV
export LI_REPO_WORKFLOW_WORKSPACE="$FIXTURE_REPO"

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

if ! reload_s2_api_key; then
  echo "test-s2-key-org-env-fixture: FAIL — reload_s2_api_key did not read org env file" >&2
  exit 1
fi

if [[ "$S2_API_KEY" != "test-key-from-org-li-env" ]]; then
  echo "test-s2-key-org-env-fixture: FAIL — unexpected key value" >&2
  exit 1
fi

if [[ "$S2_API_KEY_FILE" != "${FIXTURE_ROOT}/li/.env.github" ]]; then
  echo "test-s2-key-org-env-fixture: FAIL — expected S2_API_KEY_FILE=${FIXTURE_ROOT}/li/.env.github got ${S2_API_KEY_FILE:-}" >&2
  exit 1
fi

echo "test-s2-key-org-env-fixture: OK (org li/.env.github → ${S2_API_KEY_FILE})"
