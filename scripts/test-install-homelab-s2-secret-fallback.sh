#!/usr/bin/env bash
# Fixture — install-homelab-s2-secret.sh falls back to warm-index when homelab dir is unusable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/li-homelab-fallback.XXXXXX")"

cleanup() {
  rm -rf "$FIXTURE_DIR"
}
trap cleanup EXIT

unset S2_API_KEY S2_API_KEY_FILE
export S2_API_KEY=test-fallback-key-67890
export WARM_INDEX_PATH="$FIXTURE_DIR/warm-index"
# LI_SECRETS_DIR as an existing file — cannot mkdir or write beneath it.
export LI_SECRETS_DIR="$FIXTURE_DIR/unusable-secrets-path"
touch "$LI_SECRETS_DIR"

output="$(bash "$SCRIPT_DIR/install-homelab-s2-secret.sh" 2>&1)" || true
if ! printf '%s' "$output" | grep -q 'using warm-index drop-in'; then
  echo "test-install-homelab-s2-secret-fallback: FAIL — expected warm-index fallback log" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

dest="$WARM_INDEX_PATH/.secrets/s2-api-key"
test -f "$dest" || {
  echo "test-install-homelab-s2-secret-fallback: FAIL — missing $dest" >&2
  exit 1
}

key="$(tr -d '[:space:]' <"$dest")"
if [[ "$key" != "test-fallback-key-67890" ]]; then
  echo "test-install-homelab-s2-secret-fallback: FAIL — key mismatch" >&2
  exit 1
fi

export LI_RESEARCH_INGEST_ROOT="$REPO_ROOT"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
if ! reload_s2_api_key; then
  echo "test-install-homelab-s2-secret-fallback: FAIL — reload_s2_api_key did not find warm-index secret" >&2
  exit 1
fi

echo "test-install-homelab-s2-secret-fallback: OK ($dest)"
