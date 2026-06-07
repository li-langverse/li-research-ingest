#!/usr/bin/env bash
# Preflight: verify S2_API_KEY can reach the Datasets API (no downloads).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

usage() {
  cat <<'EOF'
Usage: verify-s2-key.sh [--quiet]

Exits 0 when S2_API_KEY is set and the Datasets API accepts it.
Exits 1 when the key is missing; 2 when the key is rejected.
EOF
}

QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet) QUIET=1; shift ;;
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

log_msg() {
  [[ "$QUIET" -eq 0 ]] && log "$@"
}

if [[ -z "${S2_API_KEY:-}" ]]; then
  log_msg "S2_API_KEY is not set"
  log_msg "Obtain a free key: https://www.semanticscholar.org/product/api"
  exit 1
fi

require_cmd curl
require_cmd jq

url="${S2_API_BASE}/release/${S2_RELEASE}/dataset/abstracts"
http_code=""
payload=""
payload="$(curl -fsSL -w '\n%{http_code}' -H "x-api-key: ${S2_API_KEY}" "$url" 2>/dev/null)" || true

if [[ -z "$payload" ]]; then
  log_msg "S2 Datasets API unreachable: $url"
  exit 2
fi

http_code="$(printf '%s' "$payload" | tail -n1)"
payload="$(printf '%s' "$payload" | sed '$d')"

if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
  log_msg "S2_API_KEY rejected (HTTP ${http_code})"
  exit 2
fi

if [[ "$http_code" != "200" ]]; then
  log_msg "S2 Datasets API error (HTTP ${http_code})"
  exit 2
fi

file_count="$(printf '%s' "$payload" | jq -r '.files | length // 0')"
release_id="$(printf '%s' "$payload" | jq -r '.release_id // "unknown"')"
log_msg "S2_API_KEY OK — release=${release_id}, abstracts partitions=${file_count}"
exit 0
