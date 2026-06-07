#!/usr/bin/env bash
# Phase 2 — Semantic Scholar papers (metadata) → /warm-index/staging/s2/papers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
# shellcheck source=lib/s2-download.sh
source "$SCRIPT_DIR/lib/s2-download.sh"

usage() {
  cat <<'EOF'
Usage: ingest-s2-papers.sh [--bootstrap] [--resume] [--max-files N]

  --bootstrap   Create staging tree only (no S2 API key)
  --resume      Skip when release marker exists (default behaviour)
  --max-files   Limit partition downloads (smoke / partial ingest)
EOF
}

MAX_FILES=0
BOOTSTRAP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap) BOOTSTRAP=1; shift ;;
    --resume) shift ;;
    --max-files)
      MAX_FILES="${2:?--max-files requires a number}"
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

if [[ "$BOOTSTRAP" -eq 1 ]]; then
  ensure_staging_tree
  log "bootstrap: created papers staging at $S2_PAPERS_DIR"
  exit 0
fi

ensure_staging_tree
s2_download_dataset "papers" "$S2_PAPERS_DIR" "$MAX_FILES"
