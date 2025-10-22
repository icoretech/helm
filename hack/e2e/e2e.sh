#!/usr/bin/env bash
set -euo pipefail

# Basic e2e for mcp-server chart using current kube context (kind or docker-desktop).
# - Installs examples and runs minimal smoke checks with in-cluster curl jobs.

NS="mcp-e2e"
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null

fail() { echo "E2E FAIL: $*" >&2; exit 1; }
hr() { echo "-----------------------------"; }

wait_ready() {
  local sel=$1 timeout=${2:-60s}
  kubectl -n "$NS" wait --for=condition=Ready pod -l "$sel" --timeout="$timeout"
}

smoke_curl() {
  local name=$1 url=$2 expect=${3:-200}
  kubectl -n "$NS" delete job "$name" --ignore-not-found >/dev/null 2>&1 || true
  cat <<EOF | kubectl -n "$NS" apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: $name
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: curl
        image: alpine:3.20
        command: ["sh","-lc"]
        args:
          - |
            apk add --no-cache curl >/dev/null
            CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 12 $url || true)
            echo ${CODE:-000}
EOF
  kubectl -n "$NS" wait --for=condition=complete job/$name --timeout=120s >/dev/null || true
  code=$(kubectl -n "$NS" logs job/$name || true)
  echo "$name => HTTP $code"
  [[ "$code" == "$expect" || "$code" == 200 || "$code" == 400 || "$code" == 404 ]] || fail "$name unexpected HTTP code $code"
}

# Gateway JSON‑RPC smoke via SSE -> messages endpoint
smoke_gw_jsonrpc() {
  local name=$1 base=$2 sse_path=$3 expect=${4:-200}
  kubectl -n "$NS" delete job "$name" --ignore-not-found >/dev/null 2>&1 || true
  cat <<EOF | kubectl -n "$NS" apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: $name
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: sh
        image: alpine:3.20
        command: ["sh","-lc"]
        args:
          - |
            apk add --no-cache curl >/dev/null
            EP=$(curl -sS --no-buffer --max-time 18 -H 'Accept: text/event-stream' $base$sse_path \
              | sed -n 's/^data: //p' | sed -n 's/.*endpoint: \(.*\)/\1/p' | head -n1)
            if [ -z "$EP" ]; then echo "000"; exit 0; fi
            CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 12 \
              -H 'Accept: application/json, text/event-stream' -H 'content-type: application/json' \
              --data '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"capabilities":{}}}' \
              $base$EP || true)
            echo ${CODE:-000}
EOF
  kubectl -n "$NS" wait --for=condition=complete job/$name --timeout=180s >/dev/null || true
  code=$(kubectl -n "$NS" logs job/$name || true)
  echo "$name => HTTP $code"
  [[ "$code" == "$expect" || "$code" == 200 || "$code" == 400 ]] || fail "$name unexpected HTTP code $code"
}

hr; echo "Install: node-server-everything example"; hr
helm upgrade --install e2e-node charts/mcp-server -n "$NS" -f charts/mcp-server/examples/node-server-everything.yaml --wait --timeout 180s
wait_ready 'app.kubernetes.io/instance=e2e-node' 60s
# Resolve ClusterIP for stability
NODE_IP=$(kubectl -n "$NS" get svc e2e-node-mcp-server -o jsonpath='{.spec.clusterIP}')
# Simple TCP reachability (Node HTTP) on 3001 using nc
kubectl -n "$NS" delete job curl-node --ignore-not-found >/dev/null 2>&1 || true
cat <<EOF | kubectl -n "$NS" apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: curl-node
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: nc
        image: alpine:3.20
        command: ["sh","-lc"]
        args: ["apk add --no-cache busybox-extras >/dev/null; nc -z -w 3 $NODE_IP 3001 && echo 200 || echo 000"]
EOF
kubectl -n "$NS" wait --for=condition=complete job/curl-node --timeout=60s >/dev/null || true
code=$(kubectl -n "$NS" logs job/curl-node || true)
echo "curl-node => TCP $code"
[[ "$code" == 200 ]] || fail "curl-node tcp failed"

echo "E2E OK"
