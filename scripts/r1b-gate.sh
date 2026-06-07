#!/usr/bin/env bash
# R1b completion gate — real corpus bytes on /warm-index (not bootstrap-only).

set -eu

WS="${LI_GOAL_WORKSPACE:-/workspace}"
INGEST="${LI_RESEARCH_INGEST_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WARM="${WARM_INDEX_PATH:-/warm-index}"
MIN_BYTES="${WARM_INGEST_MIN_BYTES:-1073741824}"
BRANCH="cursor/li-research-r1b"

_format_bytes() {
  local b="${1:-0}"
  if [[ ! "$b" =~ ^[0-9]+$ ]]; then
    echo "${b} B"
    return
  fi
  if (( b >= 1073741824 )); then
    awk -v n="$b" 'BEGIN { printf "%.2f GiB (%d B)", n/1073741824, n }'
  elif (( b >= 1048576 )); then
    awk -v n="$b" 'BEGIN { printf "%.2f MiB (%d B)", n/1048576, n }'
  elif (( b >= 1024 )); then
    awk -v n="$b" 'BEGIN { printf "%.1f KiB (%d B)", n/1024, n }'
  else
    printf '%s B' "$b"
  fi
}

fail() {
  echo "wp-li-research-r1b-warm-ingest gate: FAIL — $*" >&2
  exit 1
}

test -d "$INGEST/.git" || fail "missing git repo at $INGEST"
git -C "$INGEST" show-ref --verify --quiet "refs/remotes/origin/${BRANCH}" \
  || git -C "$INGEST" show-ref --verify --quiet "refs/heads/${BRANCH}" \
  || fail "branch ${BRANCH} not found"
test -f "$INGEST/config/datasets.toml" || fail "missing config/datasets.toml"
test -f "$INGEST/scripts/ingest-s2-abstracts.sh" || fail "missing ingest-s2-abstracts.sh"
test -f "$INGEST/scripts/run-warm-ingest.sh" || test -f "$INGEST/scripts/ingest-all.sh" \
  || fail "missing run-warm-ingest.sh"

ABSTRACTS="$WARM/staging/s2/abstracts"
test -d "$ABSTRACTS" || fail "missing $ABSTRACTS (run ./scripts/run-warm-ingest.sh --bootstrap first)"

BYTES="$(du -sb "$WARM/staging/s2" 2>/dev/null | awk '{print $1}')"
BYTES="${BYTES:-0}"

if [[ "$BYTES" -lt "$MIN_BYTES" ]]; then
  have="$(_format_bytes "$BYTES")"
  need="$(_format_bytes "$MIN_BYTES")"
  if [[ -z "${S2_API_KEY:-}" ]]; then
    fail "staging/s2=${have} (need >= ${need}); S2_API_KEY unset — ./scripts/unblock-r1b.sh or export key (issue #6)"
  fi
  fail "staging/s2=${have} (need >= ${need}); run ./scripts/run-warm-ingest.sh --resume"
fi

find "$ABSTRACTS" -type f \( -name '*.gz' -o -name '*.jsonl' -o -name '*.jsonl.gz' -o -name '*.parquet' \) -print -quit | grep -q . \
  || fail "no data files under $ABSTRACTS"

test -f "$WARM/staging/.ingest-run-state.json" || test -f "$WARM/staging/manifest.json" \
  || fail "missing .ingest-run-state.json or manifest.json under $WARM/staging"

echo "wp-li-research-r1b-warm-ingest gate: OK ($(_format_bytes "$BYTES") in staging/s2)"
