#!/usr/bin/env bash
set -euo pipefail

NS=${NS:-metamcp-prune}
REL=${REL:-metamcp-prune}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KCTX=${KUBE_CONTEXT:-docker-desktop}
TIMEOUT=${TIMEOUT:-5m}
APP="${REL}-metamcp"
CJ=/tmp/${REL}.cookies.txt
PF_LOG=/tmp/${REL}.pf.log

if ! kubectl config get-contexts -o name | grep -qx "$KCTX" 2>/dev/null; then
  echo "# requested context '$KCTX' not found. refusing to continue." >&2
  exit 1
fi

cleanup() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

HOST="$APP.$NS.svc.cluster.local"

trpc_get() {
  local route=$1
  curl --connect-timeout 2 --max-time 10 -sS -b "$CJ" -H "Host: $HOST" \
    "http://localhost:12009${route}"
}

json_has_name() {
  local name=$1
  local payload=$2
  python3 - "$name" "$payload" <<'PY'
import json
import sys

name = sys.argv[1]
payload = json.loads(sys.argv[2])
items = payload.get("result", {}).get("data", {}).get("data", [])
sys.exit(0 if any(item.get("name") == name for item in items) else 1)
PY
}

assert_present() {
  local label=$1
  local name=$2
  local payload=$3
  if ! json_has_name "$name" "$payload"; then
    echo "# expected $label '$name' to exist" >&2
    echo "$payload" >&2
    exit 1
  fi
}

assert_absent() {
  local label=$1
  local name=$2
  local payload=$3
  if json_has_name "$name" "$payload"; then
    echo "# expected $label '$name' to be pruned" >&2
    echo "$payload" >&2
    exit 1
  fi
}

signin() {
  rm -f "$CJ"
  curl --connect-timeout 2 --max-time 8 -sS -c "$CJ" -H "Content-Type: application/json" -H "Host: $HOST" \
    -d '{"email":"admin@example.com","password":"change-me","name":"Admin"}' \
    http://localhost:12009/api/auth/sign-up/email >/dev/null || true
  curl --connect-timeout 2 --max-time 8 -sS -c "$CJ" -H "Content-Type: application/json" -H "Host: $HOST" \
    -d '{"email":"admin@example.com","password":"change-me"}' \
    http://localhost:12009/api/auth/sign-in/email >/dev/null
}

echo "# using context: $KCTX"
kubectl --context "$KCTX" delete ns "$NS" --ignore-not-found --wait=true >/dev/null 2>&1 || true
kubectl --context "$KCTX" create ns "$NS" --dry-run=client -o yaml | kubectl --context "$KCTX" apply -f - >/dev/null
kubectl --context "$KCTX" -n "$NS" create secret generic metamcp-admin-credentials --from-literal=password=change-me --dry-run=client -o yaml | kubectl --context "$KCTX" -n "$NS" apply -f - >/dev/null

echo "# install initial managed set"
helm upgrade --install "$REL" "$ROOT" -n "$NS" --kube-context "$KCTX" --create-namespace \
  -f "$ROOT/examples/e2e-prune-initial.yaml" --wait --timeout "$TIMEOUT" \
  --set auth.betterAuthSecret=dev-secret

kubectl --context "$KCTX" -n "$NS" port-forward svc/"$APP" 12008:12008 12009:12009 >"$PF_LOG" 2>&1 &
PF_PID=$!
sleep 2

signin

servers_before=$(trpc_get '/trpc/frontend/frontend.mcpServers.list?input=%7B%7D')
namespaces_before=$(trpc_get '/trpc/frontend/frontend.namespaces.list?input=%7B%7D')
endpoints_before=$(trpc_get '/trpc/frontend/frontend.endpoints.list?input=%7B%7D')

assert_present "server" "legacy-stdio" "$servers_before"
assert_present "namespace" "legacy" "$namespaces_before"
assert_present "endpoint" "legacy" "$endpoints_before"

echo "# upgrade to reduced managed set"
helm upgrade --install "$REL" "$ROOT" -n "$NS" --kube-context "$KCTX" \
  -f "$ROOT/examples/e2e-prune-reduced.yaml" --wait --timeout "$TIMEOUT" \
  --set auth.betterAuthSecret=dev-secret

signin

servers_after=$(trpc_get '/trpc/frontend/frontend.mcpServers.list?input=%7B%7D')
namespaces_after=$(trpc_get '/trpc/frontend/frontend.namespaces.list?input=%7B%7D')
endpoints_after=$(trpc_get '/trpc/frontend/frontend.endpoints.list?input=%7B%7D')

assert_absent "server" "legacy-stdio" "$servers_after"
assert_absent "namespace" "legacy" "$namespaces_after"
assert_absent "endpoint" "legacy" "$endpoints_after"

echo "# prune e2e passed"
