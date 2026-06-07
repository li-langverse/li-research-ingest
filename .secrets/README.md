# Operator drop-in for S2_API_KEY

Place your Semantic Scholar Datasets API key in one of these files (gitignored):

```
.secrets/s2-api-key
```

Or set `S2_API_KEY` in the environment. Scripts auto-probe this directory via `paths.sh`.

Obtain a free key: https://www.semanticscholar.org/product/api

After wiring:

```bash
./scripts/verify-s2-key.sh
./scripts/run-warm-ingest.sh --resume
```

K8s engine pod: see [`deploy/k8s/README.md`](../deploy/k8s/README.md) and issue [#6](https://github.com/li-langverse/li-research-ingest/issues/6).
