# Operator drop-in for S2_API_KEY

Place your Semantic Scholar Datasets API key in one of these files (gitignored):

```
.secrets/s2-api-key
```

Also probed (no commit): run workspace `.secrets/`, org workspace `data/workspaces/li-langverse/.secrets/s2-api-key`, warm-index mount `/warm-index/.secrets/s2-api-key`, homelab `LI_SECRETS_DIR/s2-api-key` (default `/srv/homelab/li-research/secrets/s2-api-key`), nvme paths under `/srv/homelab/nvme/li-research/.secrets/`, K8s `/run/secrets/s2-api-key`.

Homelab install (operator, no K8s):

```bash
export S2_API_KEY=...
./scripts/install-homelab-s2-secret.sh
```

Or set `S2_API_KEY` in the environment. Scripts auto-probe these paths via `paths.sh`.

Obtain a free key: https://www.semanticscholar.org/product/api

After wiring:

```bash
./scripts/verify-s2-key.sh
./scripts/run-warm-ingest.sh --resume
```

K8s engine pod: see [`deploy/k8s/README.md`](../deploy/k8s/README.md) and issue [#6](https://github.com/li-langverse/li-research-ingest/issues/6).
