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
/srv/homelab/li-research/secrets). When LI_SECRETS_DIR is not writable, falls
back to WARM_INDEX_PATH/.secrets (engine pod drop-in). File mode 0600.

  --dir PATH  Override secrets directory (default: LI_SECRETS_DIR)

After install:
  bash scripts/discover-s2-key.sh
  bash scripts/verify-s2-key.sh
  ./scripts/unblock-r1b.sh --once
EOF
}

SECRETS_DIR="${LI_SECRETS_DIR:-/srv/homelab/li-research/secrets}"
FALLBACK_USED=0

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

_resolve_secrets_dir() {
  local dir="$1"
  if [[ -d "$dir" && -w "$dir" ]]; then
    printf '%s' "$dir"
    return 0
  fi
  if mkdir -p "$dir" 2>/dev/null && [[ -w "$dir" ]]; then
    printf '%s' "$dir"
    return 0
  fi
  return 1
}

if ! SECRETS_DIR="$(_resolve_secrets_dir "$SECRETS_DIR")"; then
  warm_root="${WARM_INDEX_ROOT:-${WARM_INDEX_PATH:-}}"
  if [[ -n "$warm_root" ]]; then
    warm_dropin="${warm_root}/.secrets"
    if SECRETS_DIR="$(_resolve_secrets_dir "$warm_dropin")"; then
      FALLBACK_USED=1
      log "LI_SECRETS_DIR not writable — using warm-index drop-in: $SECRETS_DIR"
    fi
  fi
fi

if [[ -z "${SECRETS_DIR:-}" ]] || [[ ! -w "$SECRETS_DIR" ]]; then
  echo "cannot write S2 secret — LI_SECRETS_DIR=${LI_SECRETS_DIR:-} not writable" >&2
  if [[ -n "${WARM_INDEX_PATH:-}" ]]; then
    echo "try: S2_API_KEY=... $0 --dir ${WARM_INDEX_PATH}/.secrets" >&2
  fi
  exit 1
fi

dest="${SECRETS_DIR}/s2-api-key"
umask 077
printf '%s' "$S2_API_KEY" >"$dest"
chmod 600 "$dest"
chmod 0700 "$SECRETS_DIR" 2>/dev/null || true

if [[ "$FALLBACK_USED" -eq 1 ]]; then
  log "installed warm-index S2 secret: $dest (${#S2_API_KEY} chars)"
else
  log "installed homelab S2 secret: $dest (${#S2_API_KEY} chars)"
fi
log "verify: bash scripts/discover-s2-key.sh && bash scripts/verify-s2-key.sh"
