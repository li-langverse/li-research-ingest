#!/usr/bin/env bash
# CI/local fixture — validate reload_s2_api_key reads S2_API_KEY from shared env files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/li-s2-key-env.XXXXXX")"

cleanup() {
  rm -rf "$FIXTURE_DIR"
  unset S2_API_KEY S2_API_KEY_FILE LI_GITHUB_ENV
}
trap cleanup EXIT

printf 'S2_API_KEY=test-key-from-env-file\n' >"$FIXTURE_DIR/.env.github"

unset S2_API_KEY S2_API_KEY_FILE
export LI_GITHUB_ENV="$FIXTURE_DIR/.env.github"

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

if ! reload_s2_api_key; then
  echo "test-s2-key-env-file-fixture: FAIL — reload_s2_api_key did not read env file" >&2
  exit 1
fi

if [[ "$S2_API_KEY" != "test-key-from-env-file" ]]; then
  echo "test-s2-key-env-file-fixture: FAIL — unexpected key value" >&2
  exit 1
fi

if [[ "$S2_API_KEY_FILE" != "$FIXTURE_DIR/.env.github" ]]; then
  echo "test-s2-key-env-file-fixture: FAIL — expected S2_API_KEY_FILE to point at env file" >&2
  exit 1
fi

echo "test-s2-key-env-file-fixture: OK (env file → ${S2_API_KEY_FILE})"
