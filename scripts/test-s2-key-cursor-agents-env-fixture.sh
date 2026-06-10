#!/usr/bin/env bash
# CI/local fixture — reload_s2_api_key reads S2_API_KEY from LI_CURSOR_AGENTS_ROOT/li/.env.github.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/li-s2-key-cursor.XXXXXX")"

cleanup() {
  rm -rf "$FIXTURE_ROOT"
  unset S2_API_KEY S2_API_KEY_FILE LI_CURSOR_AGENTS_ROOT LI_GITHUB_ENV
}
trap cleanup EXIT

mkdir -p "${FIXTURE_ROOT}/li"
printf 'S2_API_KEY=test-key-from-cursor-agents-li-env\n' >"${FIXTURE_ROOT}/li/.env.github"

unset S2_API_KEY S2_API_KEY_FILE LI_GITHUB_ENV
export LI_CURSOR_AGENTS_ROOT="$FIXTURE_ROOT"

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

if ! reload_s2_api_key; then
  echo "test-s2-key-cursor-agents-env-fixture: FAIL — reload_s2_api_key did not read cursor-agents env file" >&2
  exit 1
fi

if [[ "$S2_API_KEY" != "test-key-from-cursor-agents-li-env" ]]; then
  echo "test-s2-key-cursor-agents-env-fixture: FAIL — unexpected key value" >&2
  exit 1
fi

if [[ "$S2_API_KEY_FILE" != "${FIXTURE_ROOT}/li/.env.github" ]]; then
  echo "test-s2-key-cursor-agents-env-fixture: FAIL — expected S2_API_KEY_FILE=${FIXTURE_ROOT}/li/.env.github got ${S2_API_KEY_FILE:-}" >&2
  exit 1
fi

echo "test-s2-key-cursor-agents-env-fixture: OK (LI_CURSOR_AGENTS_ROOT/li/.env.github → ${S2_API_KEY_FILE})"
