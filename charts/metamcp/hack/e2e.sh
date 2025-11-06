#!/usr/bin/env bash
set -euo pipefail
NS=${NS:-metamcp}
REL=${REL:-metamcp}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PF_ENABLED=${E2E_PF:-false}
KCTX=${KUBE_CONTEXT:-docker-desktop}
# Fallback to current context if the requested one doesn't exist (helps local runs and CI portability)
if ! kubectl config get-contexts -o name | grep -qx "$KCTX" 2>/dev/null; then
  echo "# Requested context '$KCTX' not found; falling back to current context" >&2
  KCTX=$(kubectl config current-context)
fi
TIMEOUT=${TIMEOUT:-5m}

echo "# Using context: $KCTX"
echo "# Cleaning namespace $NS"
kubectl --context "$KCTX" delete ns "$NS" --ignore-not-found --wait=true >/dev/null 2>&1 || true
echo "# Installing $REL in $NS"
helm upgrade --install "$REL" "$ROOT" -n "$NS" --kube-context "$KCTX" --create-namespace -f "$ROOT/examples/e2e.yaml" --wait --timeout "$TIMEOUT" \
  --set auth.betterAuthSecret=dev-secret

echo "# Pods"
kubectl --context "$KCTX" -n "$NS" get pods -o wide

echo "# Tail important logs (metamcp, provision, user-bootstrap)"
kubectl --context "$KCTX" -n "$NS" logs deploy/$REL-$REL --tail=200 || true
kubectl --context "$KCTX" -n "$NS" logs job/$REL-$REL-provision --tail=200 || true
kubectl --context "$KCTX" -n "$NS" logs job/$REL-$REL-user-bootstrap --tail=200 || true

if [ "$PF_ENABLED" = "true" ]; then
  echo "# Port-forward service (background)"
  kubectl --context "$KCTX" -n "$NS" port-forward svc/$REL-$REL 12008:12008 12009:12009 >/tmp/${REL}.pf.log 2>&1 &
  PF=$!
  trap 'kill ${PF} >/dev/null 2>&1 || true' EXIT
  sleep 2
fi

HOST="$REL-$REL.$NS.svc.cluster.local"
echo "# Backend health"
if [ "$PF_ENABLED" = "true" ]; then
  curl --connect-timeout 2 --max-time 4 -sSf http://localhost:12009/health || true
else
  kubectl --context "$KCTX" -n "$NS" run curl-$$ --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
    curl -sSf http://$REL-$REL.$NS.svc.cluster.local:12009/health || true
fi

echo "# Authenticate and verify resources"
if [ "$PF_ENABLED" = "true" ]; then
  CJ=/tmp/${REL}.cookies.txt
  rm -f "$CJ"
  curl --connect-timeout 2 --max-time 5 -sS -c "$CJ" -H "Content-Type: application/json" -H "Host: $HOST" \
    -d '{"email":"admin@example.com","password":"change-me","name":"Admin"}' \
    http://localhost:12009/api/auth/sign-up/email >/dev/null || true
  curl --connect-timeout 2 --max-time 5 -sS -c "$CJ" -H "Content-Type: application/json" -H "Host: $HOST" \
    -d '{"email":"admin@example.com","password":"change-me"}' \
    http://localhost:12009/api/auth/sign-in/email >/dev/null
else
  kubectl --context "$KCTX" -n "$NS" run curl-$$ --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
    sh -lc "CJ=/tmp/cj.txt; HOST=$HOST; \
      curl -sS -c \$CJ -H 'Content-Type: application/json' -H \"Host: \$HOST\" -d '{\"email\":\"admin@example.com\",\"password\":\"change-me\",\"name\":\"Admin\"}' http://$REL-$REL.$NS.svc.cluster.local:12009/api/auth/sign-up/email >/dev/null || true; \
      curl -sS -c \$CJ -H 'Content-Type: application/json' -H \"Host: \$HOST\" -d '{\"email\":\"admin@example.com\",\"password\":\"change-me\"}' http://$REL-$REL.$NS.svc.cluster.local:12009/api/auth/sign-in/email >/dev/null; \
      curl -sS -b \$CJ -H \"Host: \$HOST\" 'http://$REL-$REL.$NS.svc.cluster.local:12009/trpc/frontend/frontend.mcpServers.list?input=%7B%7D' || true"
  echo
fi

echo "# tRPC: list servers/namespaces/endpoints"
if [ "$PF_ENABLED" = "true" ]; then
  curl --connect-timeout 2 --max-time 5 -sS -b "$CJ" -H "Host: $HOST" \
    "http://localhost:12009/trpc/frontend/frontend.mcpServers.list?input=%7B%7D" || true
  curl --connect-timeout 2 --max-time 5 -sS -b "$CJ" -H "Host: $HOST" \
    "http://localhost:12009/trpc/frontend/frontend.namespaces.list?input=%7B%7D" || true
  curl --connect-timeout 2 --max-time 5 -sS -b "$CJ" -H "Host: $HOST" \
    "http://localhost:12009/trpc/frontend/frontend.endpoints.list?input=%7B%7D" || true
  echo "# Backend endpoints"
  curl --connect-timeout 2 --max-time 3 -sS -D - -H 'Accept: text/event-stream' http://localhost:12009/metamcp/lab/sse -o /dev/null | head -n 20 || true
fi

if [ "$PF_ENABLED" = "true" ]; then
  kill $PF >/dev/null 2>&1 || true
fi
echo "# Final logs"mcp.icorete.ch
kubectl --context "$KCTX" -n "$NS" logs deploy/$REL-$REL --tail=200 || truemcp.icorete.ch
kubectl --context "$KCTX" -n "$NS" logs job/$REL-$REL-provision --tail=200 || true
kubectl --context "$KCTX" -n "$NS" logs job/$REL-$REL-user-bootstrap --tail=200 || true
echo "# Server pod logs"
kubectl --context "$KCTX" -n "$NS" logs -l app.kubernetes.io/component=server,mcp.icore.tech/server=http-everything --tail=120 || true
kubectl --context "$KCTX" -n "$NS" logs -l app.kubernetes.io/component=server,mcp.icore.tech/server=sse-everything --tail=120 || true
echo "# Done"
