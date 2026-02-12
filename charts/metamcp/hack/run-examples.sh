#!/usr/bin/env bash
set -euo pipefail

KCTX=${KUBE_CONTEXT:-docker-desktop}
NS=${NS:-metamcp}
TIMEOUT=${TIMEOUT:-8m}

run() { echo "+ $*"; "$@"; }

run kubectl --context "$KCTX" delete ns "$NS" --ignore-not-found
run kubectl --context "$KCTX" create ns "$NS"

echo "# Precreate demo config/secret for advanced example"
kubectl --context "$KCTX" -n "$NS" create configmap http-everything-config --from-literal=demo=ok --dry-run=client -o yaml | kubectl --context "$KCTX" -n "$NS" apply -f -
kubectl --context "$KCTX" -n "$NS" create secret generic http-everything-env --from-literal=TOKEN=dev --dry-run=client -o yaml | kubectl --context "$KCTX" -n "$NS" apply -f -
kubectl --context "$KCTX" -n "$NS" create secret generic metamcp-admin-credentials --from-literal=password=change-me --dry-run=client -o yaml | kubectl --context "$KCTX" -n "$NS" apply -f -
cat <<YAML | kubectl --context "$KCTX" -n "$NS" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sse-everything-cache
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
YAML

ROOT=$(cd "$(dirname "$0")/.." && pwd)

install_example() {
  local name=$1
  echo "\n=== Installing example: $name ==="
  run helm upgrade --install metamcp "$ROOT" \
    --namespace "$NS" --create-namespace \
    --kube-context "$KCTX" \
    -f "$ROOT/examples/$name" \
    --wait --timeout "$TIMEOUT"
  echo "# Pods"
  run kubectl --context "$KCTX" -n "$NS" get pods -o wide
  echo "# Jobs logs (if any)"
  kubectl --context "$KCTX" -n "$NS" logs job/metamcp-metamcp-provision --tail=200 || true
  kubectl --context "$KCTX" -n "$NS" logs job/metamcp-metamcp-user-bootstrap --tail=200 || true
  echo "# App logs"
  kubectl --context "$KCTX" -n "$NS" logs deploy/metamcp-metamcp --tail=200 || true
  echo "# Server pods logs"
  for p in $(kubectl --context "$KCTX" -n "$NS" get pods -l app.kubernetes.io/component=server -o name); do
    kubectl --context "$KCTX" -n "$NS" logs "$p" --tail=50 || true
  done
  echo "=== Uninstalling example: $name ==="
  run helm uninstall metamcp -n "$NS" --kube-context "$KCTX" || true
}

install_example e2e.yaml
install_example provision.yaml
install_example provision-pvc.yaml
install_example provision-advanced.yaml

echo "# Done"
