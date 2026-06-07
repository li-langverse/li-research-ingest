# Academic research service — warm ingest plan

Branch: `cursor/li-research-r1b` · Repo: `li-research-ingest`

## North star

Run bulk ingest into `/warm-index/staging/` on the engine cluster (second Intenso):

1. S2 **abstracts** (priority — run first)
2. S2 **papers** metadata
3. arXiv CS/ML OAI metadata (incremental)
4. Resume-safe state in `/warm-index/staging/.ingest-run-state.json`

**R1b milestone:** ≥ **1 GiB** under `staging/s2/` (`WARM_INGEST_MIN_BYTES`). Full 100–200 GB continues after gate; do not stop scripts once gate passes.

## Storage

| Mount in pod | Host path |
|--------------|-----------|
| `/warm-index` | `/srv/homelab/intenso-research/li-research/warm-index` |

First Intenso (`sdb`) is **lip-registry only** — do not write ingest data there.

## Phase checklist

| Phase | Key | Deliverable |
|-------|-----|-------------|
| 0 | `branch` | Push `cursor/li-research-r1b` with R1 scripts + fixes |
| 1 | `runner` | `scripts/run-warm-ingest.sh` orchestrates abstracts → papers → arxiv with resume |
| 2 | `s2-abstracts` | Run until ≥1 GiB in `staging/s2/abstracts` |
| 3 | `state` | Write `staging/.ingest-run-state.json` (bytes, datasets, timestamps) |
| 4 | `manifest` | `staging/manifest.json` listing partition files + checksums |
| 5 | `runbook` | README: `S2_API_KEY`, resume, `du -sh /warm-index/staging`, `status-warm-index.sh` |

## Completion gate

```bash
set -eu
WS="${LI_GOAL_WORKSPACE:-/workspace}"
INGEST="$WS/li-research-ingest"
WARM="${WARM_INDEX_PATH:-/warm-index}"
MIN_BYTES="${WARM_INGEST_MIN_BYTES:-1073741824}"
BRANCH="cursor/li-research-r1b"

test -d "$INGEST/.git"
git -C "$INGEST" show-ref --verify --quiet "refs/remotes/origin/${BRANCH}" \
  || git -C "$INGEST" show-ref --verify --quiet "refs/heads/${BRANCH}"
test -f "$INGEST/config/datasets.toml"
test -f "$INGEST/scripts/ingest-s2-abstracts.sh"
test -f "$INGEST/scripts/run-warm-ingest.sh" || test -f "$INGEST/scripts/ingest-all.sh"

ABSTRACTS="$WARM/staging/s2/abstracts"
test -d "$ABSTRACTS"
BYTES="$(du -sb "$WARM/staging/s2" 2>/dev/null | awk '{print $1}')"
test "${BYTES:-0}" -ge "$MIN_BYTES"

find "$ABSTRACTS" -type f \( -name '*.gz' -o -name '*.jsonl' -o -name '*.jsonl.gz' -o -name '*.parquet' \) -print -quit | grep -q .

test -f "$WARM/staging/.ingest-run-state.json" || test -f "$WARM/staging/manifest.json"

echo "wp-li-research-r1b-warm-ingest gate: OK (${BYTES} bytes in staging/s2)"
```

## Secrets

- `S2_API_KEY` — Semantic Scholar Datasets API. Required for full S2 corpus. When missing, scripts document the blocker and retry public sample paths (smoke only).
- `S2_API_KEY_FILE` — optional mounted secret path (engine pod / Vault); loaded when `S2_API_KEY` is unset.

## Related repos

| Repo | Branch |
|------|--------|
| `li-research-ingest` | `cursor/li-research-r1b` |
| `lidb` | `cursor/li-research-r1b` |
