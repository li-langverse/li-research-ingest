#!/usr/bin/env bash
# Resolve warm-index paths from config/datasets.toml with env overrides.

set -euo pipefail

_paths_repo_root() {
  local here="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  cd "$(dirname "$here")/../.." && pwd
}

REPO_ROOT="${LI_RESEARCH_INGEST_ROOT:-$(_paths_repo_root)}"
DATASETS_CONFIG="${LI_DATASETS_CONFIG:-$REPO_ROOT/config/datasets.toml}"

if [[ ! -f "$DATASETS_CONFIG" ]]; then
  echo "paths.sh: missing config: $DATASETS_CONFIG" >&2
  exit 1
fi

toml_section_value() {
  local section="$1"
  local key="$2"
  awk -v section="[$section]" -v key="$key" '
    $0 == section { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && $1 == key {
      sub(/^[^=]*=[[:space:]]*/, "")
      gsub(/^"/, "")
      gsub(/"$/, "")
      print
      exit
    }
  ' "$DATASETS_CONFIG"
}

toml_array_values() {
  local section="$1"
  local key="$2"
  awk -v section="[$section]" -v key="$key" '
    $0 == section { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && $1 == key && index($0, "[") {
      line = $0
      sub(/^[^=]*=[[:space:]]*\[/, "", line)
      gsub(/\].*$/, "", line)
      gsub(/"/, "", line)
      gsub(/[[:space:]]*,[[:space:]]*/, "\n", line)
      print line
      exit
    }
  ' "$DATASETS_CONFIG"
}

# Load S2_API_KEY from a mounted secret file when env var is unset (engine pod / Vault).
_s2_api_key_candidate_paths() {
  if [[ -n "${S2_API_KEY_FILE:-}" ]]; then
    printf '%s\n' "$S2_API_KEY_FILE"
  fi
  if [[ -n "${LI_SECRETS_DIR:-}" ]]; then
    printf '%s\n' \
      "${LI_SECRETS_DIR}/s2-api-key" \
      "${LI_SECRETS_DIR}/S2_API_KEY" \
      "${LI_SECRETS_DIR}/li-research/s2-api-key"
  fi
  # Goal workspace secrets (engine pod / agent supervisor drop-in).
  if [[ -n "${LI_GOAL_WORKSPACE:-}" ]]; then
    printf '%s\n' \
      "${LI_GOAL_WORKSPACE}/.secrets/s2-api-key" \
      "${LI_GOAL_WORKSPACE}/.secrets/S2_API_KEY" \
      "${LI_GOAL_WORKSPACE}/.secrets/li-research/s2-api-key" \
      "${LI_GOAL_WORKSPACE}/li-research-ingest/.secrets/s2-api-key" \
      "${LI_GOAL_WORKSPACE}/li-research-ingest/.secrets/S2_API_KEY" \
      "${LI_GOAL_WORKSPACE}/li-research-ingest/.secrets/li-research/s2-api-key"
  fi
  # Repo checkout drop-in (local dev / isolated agent clone).
  if [[ -n "${REPO_ROOT:-}" ]]; then
    printf '%s\n' \
      "${REPO_ROOT}/.secrets/s2-api-key" \
      "${REPO_ROOT}/.secrets/S2_API_KEY" \
      "${REPO_ROOT}/.secrets/li-research/s2-api-key"
  fi
  # Isolated agent workspace (li-cursor-agents repo-workflow clone).
  if [[ -n "${LI_REPO_WORKFLOW_WORKSPACE:-}" ]]; then
    local ws_parent ws_grandparent ws_org
    ws_parent="$(dirname "$LI_REPO_WORKFLOW_WORKSPACE")"
    ws_grandparent="$(dirname "$ws_parent")"
    ws_org="$(dirname "$ws_grandparent")"
    printf '%s\n' \
      "${ws_parent}/.secrets/s2-api-key" \
      "${ws_parent}/.secrets/S2_API_KEY" \
      "${ws_parent}/.secrets/li-research/s2-api-key" \
      "${ws_grandparent}/.secrets/s2-api-key" \
      "${ws_grandparent}/.secrets/li-research/s2-api-key" \
      "${ws_org}/.secrets/s2-api-key" \
      "${ws_org}/.secrets/S2_API_KEY" \
      "${ws_org}/.secrets/li-research/s2-api-key"
  fi
  # Warm-index mount drop-in (engine pod — secrets beside staging data).
  if [[ -n "${WARM_INDEX_PATH:-}" ]]; then
    printf '%s\n' \
      "${WARM_INDEX_PATH}/.secrets/s2-api-key" \
      "${WARM_INDEX_PATH}/.secrets/S2_API_KEY" \
      "${WARM_INDEX_PATH}/.secrets/li-research/s2-api-key"
  fi
  # Homelab host paths (engine pod bind-mount or operator drop-in).
  printf '%s\n' \
    /srv/homelab/nvme/li-research/.secrets/s2-api-key \
    /srv/homelab/nvme/li-research/warm-index/.secrets/s2-api-key \
    /srv/homelab/intenso-research/li-research/.secrets/s2-api-key \
    /srv/homelab/intenso-research/li-research/warm-index/.secrets/s2-api-key
  # Control plane / cursor-agents drop-in (org supervisor secrets).
  if [[ -n "${LI_CURSOR_AGENTS_ROOT:-}" ]]; then
    printf '%s\n' \
      "${LI_CURSOR_AGENTS_ROOT}/.secrets/s2-api-key" \
      "${LI_CURSOR_AGENTS_ROOT}/.secrets/S2_API_KEY" \
      "${LI_CURSOR_AGENTS_ROOT}/.secrets/li-research/s2-api-key"
  fi
  # Common K8s / Vault mount paths on the engine pod (no env required).
  printf '%s\n' \
    /run/secrets/s2-api-key \
    /run/secrets/S2_API_KEY \
    /run/secrets/li-research/s2-api-key \
    /run/secrets/li-research/S2_API_KEY \
    /var/secrets/s2-api-key \
    /etc/secrets/s2-api-key
}

reload_s2_api_key() {
  if [[ -n "${S2_API_KEY:-}" ]]; then
    return 0
  fi
  local path
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if [[ -r "$path" ]]; then
      S2_API_KEY="$(tr -d '[:space:]' <"$path")"
      export S2_API_KEY
      export S2_API_KEY_FILE="$path"
      return 0
    fi
  done < <(_s2_api_key_candidate_paths | awk '!seen[$0]++')
  [[ -n "${S2_API_KEY:-}" ]]
}

reload_s2_api_key || true

export WARM_INDEX_ROOT="${WARM_INDEX_PATH:-$(toml_section_value warm_index root)}"
export WARM_INDEX_STAGING="${WARM_INDEX_STAGING:-${WARM_INDEX_ROOT}/staging}"
export WARM_INDEX_BOOTSTRAP="${WARM_INDEX_BOOTSTRAP:-${WARM_INDEX_STAGING}/.ingest-bootstrap-ok}"

export S2_API_BASE="${S2_API_BASE:-$(toml_section_value s2 api_base)}"
export S2_RELEASE="${S2_RELEASE:-$(toml_section_value s2 release)}"
export S2_ABSTRACTS_DIR="${S2_ABSTRACTS_DIR:-${WARM_INDEX_STAGING}/s2/abstracts}"
export S2_PAPERS_DIR="${S2_PAPERS_DIR:-${WARM_INDEX_STAGING}/s2/papers}"
export S2_CITATIONS_DIR="${S2_CITATIONS_DIR:-${WARM_INDEX_STAGING}/s2/citations}"

export ARXIV_OAI_ENDPOINT="${ARXIV_OAI_ENDPOINT:-$(toml_section_value arxiv oai_endpoint)}"
export ARXIV_METADATA_PREFIX="${ARXIV_METADATA_PREFIX:-$(toml_section_value arxiv metadata_prefix)}"
export ARXIV_OUTPUT_DIR="${ARXIV_OUTPUT_DIR:-${WARM_INDEX_STAGING}/arxiv}"
export ARXIV_REQUEST_INTERVAL="${ARXIV_REQUEST_INTERVAL:-$(toml_section_value arxiv request_interval_sec)}"

export OPENALEX_API_BASE="${OPENALEX_API_BASE:-$(toml_section_value openalex api_base)}"
export OPENALEX_WORKS_FILTER="${OPENALEX_WORKS_FILTER:-$(toml_section_value openalex works_filter)}"
export OPENALEX_PER_PAGE="${OPENALEX_PER_PAGE:-$(toml_section_value openalex per_page)}"
export OPENALEX_OUTPUT_DIR="${OPENALEX_OUTPUT_DIR:-${WARM_INDEX_STAGING}/openalex}"
export OPENALEX_REQUEST_INTERVAL_SEC="${OPENALEX_REQUEST_INTERVAL_SEC:-$(toml_section_value openalex request_interval_sec)}"

export LIDB_SCHEMA_MIGRATION="${LIDB_SCHEMA_MIGRATION:-$(toml_section_value lidb schema_migration)}"
export LIDB_LOADER_STUB_DIR="${LIDB_LOADER_STUB_DIR:-${WARM_INDEX_STAGING}/lidb-load}"

ensure_staging_tree() {
  mkdir -p \
    "$WARM_INDEX_STAGING" \
    "$S2_ABSTRACTS_DIR" \
    "$S2_PAPERS_DIR" \
    "$S2_CITATIONS_DIR" \
    "$ARXIV_OUTPUT_DIR" \
    "$OPENALEX_OUTPUT_DIR" \
    "$LIDB_LOADER_STUB_DIR"
}

log() {
  printf '[li-research-ingest] %s\n' "$*" >&2
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "required command not found: $cmd" >&2
    exit 1
  fi
}

write_bootstrap_marker() {
  ensure_staging_tree
  date -u +"%Y-%m-%dT%H:%M:%SZ" >"$WARM_INDEX_BOOTSTRAP"
  log "bootstrap marker: $WARM_INDEX_BOOTSTRAP"
}
