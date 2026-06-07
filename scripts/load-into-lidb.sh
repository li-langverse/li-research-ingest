#!/usr/bin/env bash
# Phase 4 — stub loader: staging partitions → lidb 006_research schema

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

usage() {
  cat <<'EOF'
Usage: load-into-lidb.sh [--dry-run] [--bootstrap]

  --dry-run     Print planned load steps without touching lidb
  --bootstrap   Write loader plan manifest under staging/lidb-load
EOF
}

DRY_RUN=0
BOOTSTRAP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --bootstrap) BOOTSTRAP=1; shift ;;
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

ensure_staging_tree
manifest="$LIDB_LOADER_STUB_DIR/load-plan.json"

sources=()
add_source() {
  local kind="$1"
  local path="$2"
  if [[ -d "$path" ]] && compgen -G "$path/*" >/dev/null; then
    sources+=("{\"kind\":\"$kind\",\"path\":\"$path\"}")
  fi
}

add_source "s2_abstracts" "$S2_ABSTRACTS_DIR"
add_source "s2_papers" "$S2_PAPERS_DIR"
add_source "arxiv_oai" "$ARXIV_OUTPUT_DIR"

joined="$(printf '%s,' "${sources[@]}")"
joined="${joined%,}"

cat >"$manifest" <<EOF
{
  "schema_migration": "${LIDB_SCHEMA_MIGRATION}",
  "warm_index_root": "${WARM_INDEX_ROOT}",
  "sources": [${joined:-}],
  "status": "stub",
  "note": "Implement COPY/INSERT into lidb tables from staging partitions"
}
EOF

log "loader stub manifest: $manifest"

if [[ "$DRY_RUN" -eq 1 || "$BOOTSTRAP" -eq 1 ]]; then
  cat "$manifest"
  exit 0
fi

echo "load-into-lidb.sh: stub only — no lidb connection configured" >&2
echo "Inspect $manifest and wire to lidb migration ${LIDB_SCHEMA_MIGRATION}" >&2
exit 0
