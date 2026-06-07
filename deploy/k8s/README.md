# Engine pod — R1b warm ingest wiring

## Canonical deployment (li-cursor-agents)

**Primary wiring** lives in `li-cursor-agents/deploy/k8s/engine/deployment-li-research-ingest.yaml` (merged via `scripts/deploy-li-research-workers-k8s.ps1`):

- `S2_API_KEY_FILE=/run/secrets/s2-api-key` + `li-research-s2-api-key` secret volume
- `WARM_INDEX_PATH=/warm-index` hostPath (second Intenso)
- `LI_SECRETS_DIR=/srv/homelab/li-research/secrets` homelab drop-in

Apply from `li-cursor-agents`:

```bash
# Edit placeholder in secret-li-research-s2-api-key.yaml first
kubectl apply -f deploy/k8s/engine/secret-li-research-s2-api-key.yaml -n li-swarm
kubectl apply -f deploy/k8s/engine/deployment-li-research-ingest.yaml -n li-swarm
kubectl rollout restart deployment/li-research-ingest -n li-swarm
```

## Strategic-merge patch (this repo)

Use the files below when patching a **live** deployment without re-applying the full li-cursor-agents manifest.

## Verified state (code_implementer-1780844093895)

Live `deployment/li-research-ingest` in `li-swarm` mounts `/warm-index` and `/workspace` but **does not** mount `S2_API_KEY` yet. Ingest scripts probe `/run/secrets/s2-api-key` — absent until the patch below is applied.

| Check | Status |
|-------|--------|
| `/warm-index` mounted (second Intenso) | OK |
| `scripts/run-warm-ingest.sh` on branch | OK |
| `staging/.ingest-run-state.json` | OK (`gate_passed: false`) |
| `staging/s2/` bytes | 31,680 (sample only; need ≥ 1 GiB) |
| `S2_API_KEY` / secret mount | **missing** |

## Unblock (operator)

1. Obtain a Semantic Scholar Datasets API key: https://www.semanticscholar.org/product/api
2. Edit `s2-api-key-secret.yaml` — replace the placeholder string.
3. Apply secret + deployment patch:

```bash
kubectl apply -f deploy/k8s/s2-api-key-secret.yaml -n li-swarm
kubectl apply -f deploy/k8s/li-research-ingest-s2-patch.yaml -n li-swarm
kubectl rollout restart deployment/li-research-ingest -n li-swarm
```

4. On the pod, verify and run ingest:

```bash
cd /workspace/li-research-ingest
bash scripts/discover-s2-key.sh          # status: present
bash scripts/verify-s2-key.sh
./scripts/unblock-r1b.sh --wait-for-key 60
WARM_INDEX_PATH=/warm-index LI_RESEARCH_INGEST_ROOT=$PWD bash scripts/r1b-gate.sh
# wp-li-research-r1b-warm-ingest gate: OK
```

Or export the key directly (no K8s secret):

```bash
export S2_API_KEY=...
./scripts/run-warm-ingest.sh --resume
```

Track: [li-research-ingest#6](https://github.com/li-langverse/li-research-ingest/issues/6)

## Files

| File | Purpose |
|------|---------|
| `s2-api-key-secret.yaml` | K8s Secret (key only) |
| `li-research-ingest-s2-patch.yaml` | Strategic-merge patch for live deployment |
| `s2-api-key-secret.example.yaml` | Legacy full Deployment example (reference) |
