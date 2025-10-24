#!/usr/bin/env bash
set -euo pipefail

CHART=${1:-}
NAMESPACE=${NAMESPACE:-e2e}
TIMEOUT=${TIMEOUT:-50s}
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)

cleanup() {
  # kill port-forwards
  pkill -f "port-forward.*12008:12008" >/dev/null 2>&1 || true
  pkill -f "port-forward.*12009:12009" >/dev/null 2>&1 || true
  # delete known namespaces
  kubectl delete ns metamcp metamcp2 metamcp3 e2e --wait=true --ignore-not-found
}

helm_lint() {
  helm lint "$1"
}

install_chart() {
  local chart_dir=$1
  local release=$2
  local values=$3
  kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"
  helm upgrade --install "$release" "$chart_dir" -n "$NAMESPACE" -f "$values" --wait --timeout "$TIMEOUT"
}

case "$CHART" in
  metamcp)
    cleanup
    kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"
    # Spin up two external servers for STREAMABLE_HTTP and SSE (chart now consumes them via provision.urls)
    cat <<'YAML' | kubectl -n "$NAMESPACE" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ext-http
spec:
  replicas: 1
  selector:
    matchLabels: {app: ext-http}
  template:
    metadata: {labels: {app: ext-http}}
    spec:
      containers:
        - name: http
          image: node:24-alpine
          command: ["npx"]
          args: ["-y","@modelcontextprotocol/server-everything","streamableHttp","--port","3001"]
          ports:
            - containerPort: 3001
---
apiVersion: v1
kind: Service
metadata:
  name: ext-http
spec:
  selector: {app: ext-http}
  ports:
    - port: 3001
      targetPort: 3001
      name: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ext-sse
spec:
  replicas: 1
  selector:
    matchLabels: {app: ext-sse}
  template:
    metadata: {labels: {app: ext-sse}}
    spec:
      containers:
        - name: sse
          image: node:24-alpine
          command: ["npx"]
          args: ["-y","@modelcontextprotocol/server-everything","sse","--port","3002"]
          ports:
            - containerPort: 3002
---
apiVersion: v1
kind: Service
metadata:
  name: ext-sse
spec:
  selector: {app: ext-sse}
  ports:
    - port: 3002
      targetPort: 3002
      name: sse
YAML
    helm_lint "$ROOT/charts/metamcp"
    # Use Service FQDN for APP_URL to make in-cluster auth cookies valid for provisioning
    helm upgrade --install metamcp "$ROOT/charts/metamcp" -n "$NAMESPACE" -f "$ROOT/charts/metamcp/examples/e2e.yaml" \
      --set env.APP_URL=http://metamcp-metamcp.$NAMESPACE.svc.cluster.local:12008 --wait --timeout "$TIMEOUT"
    # Port-forward for UI convenience
    (kubectl -n "$NAMESPACE" port-forward svc/metamcp-metamcp 12008:12008 12009:12009 >/tmp/metamcp-e2e-pf.log 2>&1 &) >/dev/null 2>&1
    sleep 1
    echo "MetaMCP UI: http://localhost:12008"
    echo "Admin: admin@example.com / change-me"
    ;;
  *)
    echo "Usage: $0 metamcp [env NAMESPACE=?, TIMEOUT=?]" >&2
    exit 2
    ;;
esac

kubectl -n "$NAMESPACE" get pods -o wide
