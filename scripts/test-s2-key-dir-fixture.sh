#!/usr/bin/env bash
# CI/local fixture — validate reload_s2_api_key reads projected-secret directory mounts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/li-s2-key-dir.XXXXXX")"

cleanup() {
  rm -rf "$FIXTURE_DIR"
  unset S2_API_KEY S2_API_KEY_FILE
}
trap cleanup EXIT

mkdir -p "$FIXTURE_DIR/mount"
printf 'test-key-from-dir-mount\n' >"$FIXTURE_DIR/mount/s2-api-key"

unset S2_API_KEY S2_API_KEY_FILE
export S2_API_KEY_FILE="$FIXTURE_DIR/mount"

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

if ! reload_s2_api_key; then
  echo "test-s2-key-dir-fixture: FAIL — reload_s2_api_key did not read dir mount" >&2
  exit 1
fi

if [[ "$S2_API_KEY" != "test-key-from-dir-mount" ]]; then
  echo "test-s2-key-dir-fixture: FAIL — unexpected key value" >&2
  exit 1
fi

if [[ "$S2_API_KEY_FILE" != "$FIXTURE_DIR/mount/s2-api-key" ]]; then
  echo "test-s2-key-dir-fixture: FAIL — expected file path inside dir mount" >&2
  exit 1
fi

echo "test-s2-key-dir-fixture: OK (dir mount → ${S2_API_KEY_FILE})"
