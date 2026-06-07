#!/usr/bin/env bash
# Completion gate from docs/plans/academic-research-service.md

set -eu

WS="${LI_GOAL_WORKSPACE:-/workspace}"
INGEST="${LI_RESEARCH_INGEST_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WARM="${WARM_INDEX_PATH:-/warm-index}"

test -d "$INGEST/.git"
test -f "$INGEST/config/datasets.toml"
test -x "$INGEST/scripts/ingest-s2-abstracts.sh" || test -f "$INGEST/scripts/ingest-s2-abstracts.sh"
test -f "$INGEST/scripts/ingest-arxiv-oai.sh"
test -d "$WARM/staging" || mkdir -p "$WARM/staging"
test -f "$WARM/staging/.ingest-bootstrap-ok" || test -d "$WARM/staging/s2"
echo "wp-li-research-warm-ingest gate: OK"
