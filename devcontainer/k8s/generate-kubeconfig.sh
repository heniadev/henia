#!/usr/bin/env bash
# Run this yourself, against your real k3s cluster (i.e. with a kubectl
# context that already has sufficient access — this script doesn't grant
# itself anything). NOT run inside the devcontainer, which has no cluster
# access until this script's output exists.
#
# Applies the read-only RBAC (rbac.yaml) if not already applied, mints a
# ServiceAccount token scoped to just that identity, and writes a
# standalone kubeconfig — nothing from your own kubeconfig (other clusters,
# your own user credentials) leaks into it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="claude-devcontainer"
SA_NAME="claude-devcontainer"
CLUSTER_NAME="${CLUSTER_NAME:-k3s}"
TOKEN_DURATION="${TOKEN_DURATION:-87600h}"
OUT_FILE="$SCRIPT_DIR/../kubeconfig.yaml"

: "${API_SERVER:?Set API_SERVER, e.g. API_SERVER=https://10.242.0.10:6443 $0}"

echo "Applying RBAC (namespace, ServiceAccount, ClusterRoleBinding to 'view')..." >&2
kubectl apply -f "$SCRIPT_DIR/rbac.yaml"

echo "Minting a ${TOKEN_DURATION} token for ${SA_NAME}..." >&2
TOKEN="$(kubectl create token "$SA_NAME" -n "$NAMESPACE" --duration "$TOKEN_DURATION")"

CA_DATA="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
if [ -z "$CA_DATA" ]; then
  echo "Could not read certificate-authority-data from your current kubectl context." >&2
  echo "Make sure the context you want is selected (kubectl config current-context)." >&2
  exit 1
fi

cat > "$OUT_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: ${CLUSTER_NAME}
    cluster:
      server: ${API_SERVER}
      certificate-authority-data: ${CA_DATA}
contexts:
  - name: ${SA_NAME}
    context:
      cluster: ${CLUSTER_NAME}
      user: ${SA_NAME}
      namespace: ${NAMESPACE}
current-context: ${SA_NAME}
users:
  - name: ${SA_NAME}
    user:
      token: ${TOKEN}
EOF

chmod 600 "$OUT_FILE"
echo "Wrote $OUT_FILE (token valid ${TOKEN_DURATION}). Re-run this script to refresh before it expires." >&2
