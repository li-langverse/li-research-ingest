#!/usr/bin/env bash
# Operator helper — print kubectl steps to wire S2_API_KEY on li-research-ingest.
# Does not apply changes; requires cluster admin + a real API key in the secret yaml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NS="${LI_GOAL_NAMESPACE:-li-swarm}"
DEPLOY="${LI_GOAL_DEPLOYMENT_NAME:-li-research-ingest}"

cat <<EOF
=== R1b S2 key wiring (operator) ===

Deployment: ${DEPLOY} (namespace ${NS})
Warm index:  \${WARM_INDEX_PATH:-/warm-index}

1. Edit secret placeholder:
     \$EDITOR ${REPO_ROOT}/deploy/k8s/s2-api-key-secret.yaml

2. Apply secret + mount patch:
     kubectl apply -f ${REPO_ROOT}/deploy/k8s/s2-api-key-secret.yaml -n ${NS}
     kubectl apply -f ${REPO_ROOT}/deploy/k8s/li-research-ingest-s2-patch.yaml -n ${NS}
     kubectl rollout restart deployment/${DEPLOY} -n ${NS}

3. Verify on pod:
     bash ${REPO_ROOT}/scripts/discover-s2-key.sh
     bash ${REPO_ROOT}/scripts/verify-s2-key.sh
     bash ${REPO_ROOT}/scripts/unblock-r1b.sh --once --wait-for-key 60

Docs: ${REPO_ROOT}/deploy/k8s/README.md
Issue: https://github.com/li-langverse/li-research-ingest/issues/6
EOF
