#!/usr/bin/env bash
# Operator diagnostic: report S2_API_KEY env + probed secret mount paths.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

usage() {
  cat <<'EOF'
Usage: discover-s2-key.sh [--quiet]

  --quiet  Suppress path listing; exit 0 when key present, 1 when missing
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

if [[ "$QUIET" -eq 0 ]]; then
  printf 'S2 key discovery (%s)\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi

if [[ -n "${S2_API_KEY:-}" ]]; then
  src="env"
  [[ -n "${S2_API_KEY_FILE:-}" ]] && src="file:${S2_API_KEY_FILE}"
  [[ "$QUIET" -eq 0 ]] && printf '  status: present (source=%s)\n' "$src"
  verify_args=()
  [[ "$QUIET" -eq 1 ]] && verify_args+=(--quiet)
  exec bash "$SCRIPT_DIR/verify-s2-key.sh" "${verify_args[@]}"
fi

[[ "$QUIET" -eq 0 ]] && printf '  status: missing\n'
[[ "$QUIET" -eq 0 ]] && printf '  probed paths:\n'
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ -f "$path" ]]; then
    [[ "$QUIET" -eq 0 ]] && printf '    [readable] %s\n' "$path"
  else
    [[ "$QUIET" -eq 0 ]] && printf '    [absent]   %s\n' "$path"
  fi
done < <(_s2_api_key_candidate_paths | awk '!seen[$0]++')

[[ "$QUIET" -eq 0 ]] && printf '\n  unblock: export S2_API_KEY=... or mount secret at one of the paths above\n'
[[ "$QUIET" -eq 0 ]] && printf '           https://www.semanticscholar.org/product/api\n'
exit 1
