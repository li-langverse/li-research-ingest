#!/usr/bin/env bash
# Operator helper — write S2_API_KEY to LI_SECRETS_DIR for engine pod auto-probe.
# Does not commit secrets; writes only to the homelab secrets mount.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

usage() {
  cat <<'EOF'
Usage: install-homelab-s2-secret.sh [--dir PATH]

Writes S2_API_KEY (env) to LI_SECRETS_DIR/s2-api-key (default dir from env or
/srv/homelab/li-research/secrets). File mode 0600. Does not print the key.

  --dir PATH  Override secrets directory (default: LI_SECRETS_DIR)

After install:
  bash scripts/discover-s2-key.sh
  bash scripts/verify-s2-key.sh
  ./scripts/unblock-r1b.sh --once
EOF
}

SECRETS_DIR="${LI_SECRETS_DIR:-/srv/homelab/li-research/secrets}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      SECRETS_DIR="${2:?--dir requires a path}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${S2_API_KEY:-}" ]]; then
  echo "S2_API_KEY is required in the environment" >&2
  echo "Obtain a key: https://www.semanticscholar.org/product/api" >&2
  exit 1
fi

dest="${SECRETS_DIR}/s2-api-key"
mkdir -p "$SECRETS_DIR"
umask 077
printf '%s' "$S2_API_KEY" >"$dest"
chmod 600 "$dest"

log "installed homelab S2 secret: $dest (${#S2_API_KEY} chars)"
log "verify: bash scripts/discover-s2-key.sh && bash scripts/verify-s2-key.sh"
