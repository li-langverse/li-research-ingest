#!/usr/bin/env bash
# Fixture — install-homelab-s2-secret.sh writes key without touching live homelab paths.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/li-homelab-secret.XXXXXX")"

cleanup() {
  rm -rf "$FIXTURE_DIR"
}
trap cleanup EXIT

unset S2_API_KEY S2_API_KEY_FILE
export S2_API_KEY=test-homelab-key-12345
export LI_SECRETS_DIR="$FIXTURE_DIR/secrets"

bash "$SCRIPT_DIR/install-homelab-s2-secret.sh"

dest="$LI_SECRETS_DIR/s2-api-key"
test -f "$dest" || {
  echo "test-install-homelab-s2-secret: FAIL — missing $dest" >&2
  exit 1
}

perms="$(stat -c '%a' "$dest")"
if [[ "$perms" != "600" ]]; then
  echo "test-install-homelab-s2-secret: FAIL — expected mode 600, got $perms" >&2
  exit 1
fi

key="$(tr -d '[:space:]' <"$dest")"
if [[ "$key" != "test-homelab-key-12345" ]]; then
  echo "test-install-homelab-s2-secret: FAIL — key mismatch" >&2
  exit 1
fi

export LI_RESEARCH_INGEST_ROOT="$REPO_ROOT"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
if ! reload_s2_api_key; then
  echo "test-install-homelab-s2-secret: FAIL — reload_s2_api_key did not find homelab secret" >&2
  exit 1
fi

echo "test-install-homelab-s2-secret: OK ($dest)"
