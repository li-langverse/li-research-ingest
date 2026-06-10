#!/usr/bin/env bash
# CI/local fixture — validate persist_s2_api_key_dropin writes env key to warm-index .secrets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/li-s2-key-persist.XXXXXX")"

cleanup() {
  rm -rf "$FIXTURE_ROOT"
  unset S2_API_KEY S2_API_KEY_FILE WARM_INDEX_PATH
}
trap cleanup EXIT

export WARM_INDEX_PATH="$FIXTURE_ROOT"
export S2_API_KEY="test-key-from-env-persist"
unset S2_API_KEY_FILE

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

dropin="${WARM_INDEX_ROOT}/.secrets/s2-api-key"
if [[ ! -f "$dropin" ]]; then
  echo "test-s2-key-persist-fixture: FAIL — drop-in not created at $dropin" >&2
  exit 1
fi

if [[ "$(tr -d '[:space:]' <"$dropin")" != "test-key-from-env-persist" ]]; then
  echo "test-s2-key-persist-fixture: FAIL — unexpected drop-in contents" >&2
  exit 1
fi

if [[ "$S2_API_KEY_FILE" != "$dropin" ]]; then
  echo "test-s2-key-persist-fixture: FAIL — S2_API_KEY_FILE not updated to drop-in" >&2
  exit 1
fi

# Second call must not overwrite an existing drop-in.
printf 'existing-on-disk\n' >"$dropin"
persist_s2_api_key_dropin
if [[ "$(tr -d '[:space:]' <"$dropin")" != "existing-on-disk" ]]; then
  echo "test-s2-key-persist-fixture: FAIL — persist overwrote existing drop-in" >&2
  exit 1
fi

echo "test-s2-key-persist-fixture: OK (env key → ${dropin})"
