#!/usr/bin/env bash
# Public-API warm index gate — arXiv OAI + OpenAlex REST (no S2 key).

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INGEST="${LI_RESEARCH_INGEST_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
WARM="${WARM_INDEX_PATH:-/warm-index}"
MIN_BYTES="${WARM_INGEST_MIN_BYTES:-104857600}"
BRANCH="${WARM_INGEST_BRANCH:-cursor/li-research-public-index}"

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

fail() {
  echo "wp-li-research-public-index gate: FAIL — $*" >&2
  exit 1
}

test -d "$INGEST/.git" || fail "missing git repo"
if [[ "${PUBLIC_INDEX_GATE_SKIP_BRANCH:-}" != 1 ]]; then
  git -C "$INGEST" show-ref --verify --quiet "refs/remotes/origin/${BRANCH}" \
    || git -C "$INGEST" show-ref --verify --quiet "refs/heads/${BRANCH}" \
    || fail "branch ${BRANCH} not found"
fi

test -f "$INGEST/scripts/ingest-openalex.sh" || fail "missing ingest-openalex.sh"
test -f "$INGEST/scripts/ingest-arxiv-oai.sh" || fail "missing ingest-arxiv-oai.sh"
test -f "$INGEST/scripts/run-public-ingest.sh" || fail "missing run-public-ingest.sh"

test -d "$WARM/staging/openalex" || fail "missing $WARM/staging/openalex"
test -d "$WARM/staging/arxiv" || fail "missing $WARM/staging/arxiv"

bytes_openalex="$(du -sb "$WARM/staging/openalex" 2>/dev/null | awk '{print $1}')"
bytes_arxiv="$(du -sb "$WARM/staging/arxiv" 2>/dev/null | awk '{print $1}')"
bytes_openalex="${bytes_openalex:-0}"
bytes_arxiv="${bytes_arxiv:-0}"
bytes_total=$((bytes_openalex + bytes_arxiv))

test "$bytes_total" -ge "$MIN_BYTES" \
  || fail "public corpus ${bytes_total} B < min ${MIN_BYTES} B — run ./scripts/run-public-ingest.sh --resume"

find "$WARM/staging/openalex" -type f -name 'works-*.jsonl' -print -quit | grep -q . \
  || fail "no OpenAlex works-*.jsonl files"

find "$WARM/staging/arxiv" -type f -name '*.xml' -print -quit | grep -q . \
  || fail "no arXiv XML files"

test -f "$WARM/staging/.ingest-run-state.json" || test -f "$WARM/staging/manifest.json" \
  || fail "missing ingest state/manifest"

echo "wp-li-research-public-index gate: OK (${bytes_total} bytes public corpus)"
