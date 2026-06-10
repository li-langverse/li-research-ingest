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

configured_file="${S2_API_KEY_FILE:-}"
if [[ -n "$configured_file" && ! -f "$configured_file" ]]; then
  if [[ -d "$configured_file" ]]; then
    dir_files="$(find "$configured_file" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l | tr -d '[:space:]')"
    dir_files="${dir_files:-0}"
    if [[ "$dir_files" -eq 0 && "$QUIET" -eq 0 ]]; then
      printf '  configured S2_API_KEY_FILE=%s — empty directory mount (K8s secret not applied)\n' "$configured_file"
      printf '        fix: kubectl apply -f deploy/k8s/s2-api-key-secret.yaml -n %s\n' "${LI_GOAL_NAMESPACE:-li-swarm}"
    fi
  elif [[ "$QUIET" -eq 0 ]]; then
    printf '  configured S2_API_KEY_FILE=%s — path missing\n' "$configured_file"
  fi
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
[[ "$QUIET" -eq 0 ]] && printf '  probed env files:\n'
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ -f "$path" ]]; then
    if grep -qE '^[[:space:]]*S2_API_KEY=' "$path" 2>/dev/null; then
      [[ "$QUIET" -eq 0 ]] && printf '    [has-key]  %s\n' "$path"
    else
      [[ "$QUIET" -eq 0 ]] && printf '    [no-key]   %s\n' "$path"
    fi
  else
    [[ "$QUIET" -eq 0 ]] && printf '    [absent]   %s\n' "$path"
  fi
done < <(_s2_env_file_candidate_paths | awk '!seen[$0]++')
[[ "$QUIET" -eq 0 ]] && printf '  probed paths:\n'
empty_dirs=0
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ -f "$path" ]]; then
    [[ "$QUIET" -eq 0 ]] && printf '    [readable] %s\n' "$path"
  elif [[ -d "$path" ]]; then
    dir_files="$(find "$path" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l | tr -d '[:space:]')"
    dir_files="${dir_files:-0}"
    if [[ "$dir_files" -gt 0 ]]; then
      [[ "$QUIET" -eq 0 ]] && printf '    [dir-files]  %s (%s file(s))\n' "$path" "$dir_files"
    else
      empty_dirs=$((empty_dirs + 1))
      [[ "$QUIET" -eq 0 ]] && printf '    [empty-dir] %s\n' "$path"
    fi
  else
    [[ "$QUIET" -eq 0 ]] && printf '    [absent]   %s\n' "$path"
  fi
done < <(_s2_api_key_candidate_paths | awk '!seen[$0]++')

if [[ "$QUIET" -eq 0 && "$empty_dirs" -gt 0 ]]; then
  printf '\n  note: %d empty directory mount(s) — K8s secret projected but file missing\n' "$empty_dirs"
  printf '        apply deploy/k8s/s2-api-key-secret.yaml + li-research-ingest-s2-patch.yaml\n'
fi
if [[ "$QUIET" -eq 0 ]]; then
  warm_secrets_dir="${WARM_INDEX_ROOT}/.secrets"
  if [[ -d "$warm_secrets_dir" && -w "$warm_secrets_dir" ]]; then
    printf '\n  warm-index drop-in (writable): %s/s2-api-key\n' "$warm_secrets_dir"
    printf '        S2_API_KEY=... ./scripts/install-homelab-s2-secret.sh --dir %s\n' "$warm_secrets_dir"
  fi
  printf '\n  unblock: export S2_API_KEY=... or mount secret at one of the paths above\n'
  printf '           https://www.semanticscholar.org/product/api\n'
fi
exit 1
