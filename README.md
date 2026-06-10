# li-research-ingest

Bulk ingest for the Li research warm index on the engine cluster (**second Intenso**).

Target corpus: **100–200 GB** under `/warm-index/staging/` (abstracts first, then papers metadata, arXiv CS/ML OAI, citations subset later).

**R1b milestone:** ≥ **1 GiB** under `staging/s2/` (`WARM_INGEST_MIN_BYTES`, default `1073741824`). Full corpus ingest continues after the gate passes.

## Storage layout

| Mount in pod | Host path |
|--------------|-----------|
| `/warm-index` | `/srv/homelab/nvme/li-research/warm-index` (second Intenso) |
| `/warm-index` | `/srv/homelab/intenso-research/li-research/warm-index` (alt host bind) |

**Do not** write ingest data to the first Intenso (`sdb`) — that volume is **lip-registry only**.

```
/warm-index/
└── staging/
    ├── .ingest-run-state.json   # resume-safe bytes + dataset status
    ├── manifest.json            # partition paths + sha256 checksums
    ├── .ingest-bootstrap-ok     # smoke / layout marker
    ├── s2/
    │   ├── abstracts/            # S2 abstracts partitions (.jsonl.gz)
    │   ├── papers/               # S2 papers metadata
    │   └── citations/            # reserved for citation-edge subset
    ├── arxiv/                    # OAI ListRecords XML per CS/ML set
    └── lidb-load/
        └── load-plan.json        # loader stub manifest
```

Paths are defined in [`config/datasets.toml`](config/datasets.toml). Override with env vars (`WARM_INDEX_PATH`, `S2_ABSTRACTS_DIR`, …).

## Secrets

| Variable | Purpose |
|----------|---------|
| `S2_API_KEY` | Semantic Scholar Datasets API (`x-api-key` header). **Required for R1b ≥1 GiB gate.** Obtain at [Semantic Scholar API](https://www.semanticscholar.org/product/api). |
| `S2_API_KEY_FILE` | Path to a mounted secret file containing the API key (used when `S2_API_KEY` is unset). Auto-probed: `/run/secrets/s2-api-key`, `/run/secrets/S2_API_KEY`, `/run/secrets/li-research/s2-api-key`, … |
| `LI_SECRETS_DIR` | Optional homelab secrets directory; auto-probes `$LI_SECRETS_DIR/s2-api-key` and `$LI_SECRETS_DIR/li-research/s2-api-key`. |
| `LI_GOAL_WORKSPACE` | When set, also probes `$LI_GOAL_WORKSPACE/.secrets/s2-api-key` (supervisor drop-in). |
| `LI_GITHUB_ENV` / `LI_SHARED_ENV` | Shared env files (e.g. `li/.env.github`) — `S2_API_KEY=...` line auto-loaded when unset. |
| `LI_RESEARCH_S2_ENV_FILE` | Explicit env file path for `S2_API_KEY` (overrides default probe order). |
| Repo `.secrets/` | Probes `$LI_RESEARCH_INGEST_ROOT/.secrets/s2-api-key` for local / agent-clone drop-in. |

### Blocker: `S2_API_KEY` not wired

When `S2_API_KEY` is unset, scripts retry public sample paths (`--samples` / ai2-s2ag/samples) for smoke testing. Samples are **far below** the 1 GiB gate. Export `S2_API_KEY` on the engine pod (Vault wiring pending) and re-run.

**K8s wiring** (engine pod, second Intenso mount): [`deploy/k8s/README.md`](deploy/k8s/README.md) — apply `s2-api-key-secret.yaml` + `li-research-ingest-s2-patch.yaml` to mount `/run/secrets/s2-api-key` (auto-probed by `paths.sh`). Operator helper: `./scripts/operator-wire-s2-key.sh`. Tracked in [#6](https://github.com/li-langverse/li-research-ingest/issues/6).

**Current blocker (verified code_implementer-1781112730391, 2026-06-10):** `/warm-index` mounted (~808 GiB avail; `warm_index_disk.avail_bytes=867428540416`). `S2_API_KEY_FILE=/run/secrets/s2-api-key` is configured on the pod but the mount is an **empty directory** (`configured_file_empty=true`, `empty_dir_mounts=1`, `probed_paths=36`) — apply `deploy/k8s/s2-api-key-secret.yaml` per [#6](https://github.com/li-langverse/li-research-ingest/issues/6). No `S2_API_KEY` in `li/.env.github` (GH_TOKEN only), `LI_SECRETS_DIR` (`/srv/homelab/li-research/secrets` exists, not writable), repo `.secrets/`, or homelab paths. `/warm-index/.secrets/` writable (mode 0700) for operator drop-in — `discover-s2-key.sh`, `status-warm-index.sh`, and `preflight-r1b.sh` print this path when writable. When `S2_API_KEY` is exported in env, `paths.sh` auto-persists it to `/warm-index/.secrets/s2-api-key` for resume across agent runs. Agent pass polled 60s (`LI_GOAL_SELF_UNBLOCK=1`) — key still missing. Staging/s2 remains sample-only (31,680 B, 0% of 1 GiB gate). arXiv OAI complete (~8.5 GiB, 2,363 files, 4 sets). Operator: add `S2_API_KEY` to `li/.env.github` (auto-probed), K8s secret (`./scripts/operator-wire-s2-key.sh`), homelab drop-in (`S2_API_KEY=... ./scripts/install-homelab-s2-secret.sh`), warm-index drop-in (`S2_API_KEY=... ./scripts/install-homelab-s2-secret.sh --dir /warm-index/.secrets`), or `.secrets/s2-api-key` (see [`.secrets/README.md`](.secrets/README.md)). Re-run `./scripts/unblock-r1b.sh` or `./scripts/agent-r1b-pass.sh --wait-for-key 3600` after wiring. Phase checklist: branch/runner/state/manifest/runbook **done**; s2_abstracts **blocked** pending key. Traceability: `/warm-index/staging/.ingest-run-state.json` and `.agent-r1b-report.json` (run `code_implementer-1781112730391`).

```bash
export S2_API_KEY=...
./scripts/verify-s2-key.sh          # preflight — exits 0 when key works
./scripts/run-warm-ingest.sh --resume
```

arXiv OAI harvest runs without a key (3 s/request policy).

## Ingest scripts

| Phase | Script | Output |
|-------|--------|--------|
| 0 | `config/datasets.toml` | warm-index paths |
| **runner** | **`scripts/run-warm-ingest.sh`** | **orchestrates all phases + state/manifest** |
| status | `scripts/status-warm-index.sh` | gate progress + disk usage snapshot |
| preflight | `scripts/preflight-r1b.sh` | key discovery + status + R1b gate in one pass |
| gate loop | `scripts/gate-loop.sh` | poll `S2_API_KEY`, run ingest, retry until R1b gate passes |
| **unblock** | **`scripts/unblock-r1b.sh`** | **operator entry — key discovery + gate-loop (default 1h key poll)** |
| agent pass | `scripts/agent-r1b-pass.sh` | supervisor / code_implementer entry — JSON report + gate exit code |
| key probe | `scripts/discover-s2-key.sh` | S2_API_KEY env + K8s secret mount diagnostics |
| homelab key | `scripts/install-homelab-s2-secret.sh` | write `S2_API_KEY` → `LI_SECRETS_DIR/s2-api-key` |
| 1 | `scripts/ingest-s2-abstracts.sh` | `/warm-index/staging/s2/abstracts` |
| 2 | `scripts/ingest-s2-papers.sh` | `/warm-index/staging/s2/papers` |
| 3 | `scripts/ingest-arxiv-oai.sh` | `/warm-index/staging/arxiv` |
| 4 | `scripts/load-into-lidb.sh` | stub → `lidb` migration `006_research.sql` |

All scripts support **`--bootstrap`** for layout-only runs (no API key, writes `.ingest-bootstrap-ok`).

### Quick start (engine pod)

```bash
export WARM_INDEX_PATH=/warm-index
export S2_API_KEY=...   # required for ≥1 GiB R1b gate

# Full warm ingest (abstracts until gate → papers → arXiv)
./scripts/run-warm-ingest.sh

# Resume after interrupt (skips completed partitions)
./scripts/run-warm-ingest.sh --resume

# Poll for Vault-mounted S2_API_KEY_FILE before bulk download (engine pod)
./scripts/run-warm-ingest.sh --wait-for-key 3600 --resume

# Supervisor loop: retry ingest until ≥1 GiB gate passes (engine pod / goal loop)
./scripts/unblock-r1b.sh
# or lower-level:
./scripts/gate-loop.sh --wait-for-key 3600 --sleep 300

# Gate / disk snapshot
./scripts/status-warm-index.sh

# Layout + bootstrap marker (smoke, no downloads)
./scripts/run-warm-ingest.sh --bootstrap
```

Individual phases:

```bash
./scripts/ingest-s2-abstracts.sh
./scripts/ingest-s2-papers.sh
./scripts/ingest-arxiv-oai.sh
./scripts/load-into-lidb.sh --bootstrap
```

Partial / smoke downloads:

```bash
./scripts/ingest-s2-abstracts.sh --max-files 1
./scripts/ingest-s2-abstracts.sh --samples   # public sample shard, no API key
./scripts/ingest-arxiv-oai.sh --set cs:cs:LG --max-records 50
./scripts/run-warm-ingest.sh --max-s2-files 1
```

## Runbook

### Disk check

```bash
du -sh /warm-index /warm-index/staging /warm-index/staging/s2/*
df -h /warm-index
```

### Resume

- **Orchestrator**: re-run `./scripts/run-warm-ingest.sh --resume` — state in `staging/.ingest-run-state.json`.
- **S2**: partition files are skipped when present; release markers live beside data:
  - `.../abstracts/.release-latest-abstracts.ok`
  - `.../papers/.release-latest-papers.ok`
- **arXiv**: per-set markers `.../arxiv/.cs__cs__LG.ok` (set name with `/` → `_`).
- Ingest **continues past the 1 GiB gate** toward the full 100–200 GB target; do not stop the runner once the gate passes.

### State and manifest

After each phase, `run-warm-ingest.sh` writes:

- `staging/.ingest-run-state.json` — byte counts, dataset status, gate flag
- `staging/manifest.json` — partition file paths + sha256 checksums

### Diffs (S2 incremental)

Use the [S2 Datasets diff endpoint](https://api.semanticscholar.org/datasets/v1/diff) between release IDs when upgrading snapshots. Record `release_id` from the download JSON before applying diffs.

### Completion gates

R0 smoke (layout only):

```bash
WARM_INDEX_PATH=/warm-index LI_RESEARCH_INGEST_ROOT=$PWD bash scripts/smoke-gate.sh
# wp-li-research-warm-ingest gate: OK
```

R1b warm ingest (real bytes):

```bash
WARM_INDEX_PATH=/warm-index LI_RESEARCH_INGEST_ROOT=$PWD bash scripts/r1b-gate.sh
# wp-li-research-r1b-warm-ingest gate: OK (N bytes in staging/s2)
```

## CLI (R0)

TypeScript CLI stubs remain for job enqueue via gateway:

| Command | Description |
|---------|-------------|
| `li-research-ingest kinds` | List `lidb.research_job` kinds |
| `li-research-ingest batch <manifest>` | *(planned)* enqueue `ingest_batch` |

Build: `npm run build && npm test`

## Related

- Plan: [`docs/plans/academic-research-service.md`](docs/plans/academic-research-service.md)
- Schema: `lidb/migrations/006_research.sql`
- Gateway / MCP: `li-research-gateway`, `li-research-mcp`

## Do not

- Write to `/srv/homelab/external` (LiP disk)
- Mirror full OpenAlex (~1.6 TB)
- Pass R1b gate with only `.ingest-bootstrap-ok` and empty dirs
