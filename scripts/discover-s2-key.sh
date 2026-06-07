#!/usr/bin/env bash
# Operator diagnostic: report S2_API_KEY env + probed secret mount paths.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

printf 'S2 key discovery (%s)\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ -n "${S2_API_KEY:-}" ]]; then
  src="env"
  [[ -n "${S2_API_KEY_FILE:-}" ]] && src="file:${S2_API_KEY_FILE}"
  printf '  status: present (source=%s)\n' "$src"
  exec bash "$SCRIPT_DIR/verify-s2-key.sh" "$@"
fi

printf '  status: missing\n'
printf '  probed paths:\n'
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ -r "$path" ]]; then
    printf '    [readable] %s\n' "$path"
  else
    printf '    [absent]   %s\n' "$path"
  fi
done < <(_s2_api_key_candidate_paths | awk '!seen[$0]++')

printf '\n  unblock: export S2_API_KEY=... or mount secret at one of the paths above\n'
printf '           https://www.semanticscholar.org/product/api\n'
exit 1
