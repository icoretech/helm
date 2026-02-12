#!/usr/bin/env bash
set -euo pipefail
NS=${NS:-metamcp}
REL=${REL:-metamcp}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PF_ENABLED=${E2E_PF:-false}
KCTX=${KUBE_CONTEXT:-docker-desktop}
# Safety: never fall back to current context unless explicitly allowed.
if ! kubectl config get-contexts -o name | grep -qx "$KCTX" 2>/dev/null; then
  if [ "${ALLOW_CONTEXT_FALLBACK:-false}" = "true" ]; then
    echo "# Requested context '$KCTX' not found; falling back to current context" >&2
    KCTX=$(kubectl config current-context)
  else
    echo "# Requested context '$KCTX' not found. Refusing to continue." >&2
    echo "# Tip: set KUBE_CONTEXT to an existing kubecontext (recommended: docker-desktop)." >&2
    exit 1
  fi
fi
TIMEOUT=${TIMEOUT:-5m}
APP="${REL}-metamcp"

echo "# Using context: $KCTX"
echo "# Cleaning namespace $NS"
kubectl --context "$KCTX" delete ns "$NS" --ignore-not-found --wait=true >/dev/null 2>&1 || true

echo "# Precreate Secret for users[].passwordFrom.secretKeyRef (examples expect this)"
kubectl --context "$KCTX" create ns "$NS" --dry-run=client -o yaml | kubectl --context "$KCTX" apply -f - >/dev/null
kubectl --context "$KCTX" -n "$NS" create secret generic metamcp-admin-credentials --from-literal=password=change-me --dry-run=client -o yaml | kubectl --context "$KCTX" -n "$NS" apply -f - >/dev/null

echo "# Installing $REL in $NS"
helm upgrade --install "$REL" "$ROOT" -n "$NS" --kube-context "$KCTX" --create-namespace -f "$ROOT/examples/e2e.yaml" --wait --timeout "$TIMEOUT" \
  --set auth.betterAuthSecret=dev-secret

echo "# Pods"
kubectl --context "$KCTX" -n "$NS" get pods -o wide

echo "# Tail important logs (metamcp, provision, user-bootstrap)"
kubectl --context "$KCTX" -n "$NS" logs deploy/$APP --tail=200 || true
kubectl --context "$KCTX" -n "$NS" logs job/$APP-provision --tail=200 || true
kubectl --context "$KCTX" -n "$NS" logs job/$APP-user-bootstrap --tail=200 || true

if [ "$PF_ENABLED" = "true" ]; then
  echo "# Port-forward service (background)"
  kubectl --context "$KCTX" -n "$NS" port-forward svc/$APP 12008:12008 12009:12009 >/tmp/${REL}.pf.log 2>&1 &
  PF=$!
  trap 'kill ${PF} >/dev/null 2>&1 || true' EXIT
  sleep 2
fi

HOST="$APP.$NS.svc.cluster.local"
echo "# Backend health"
if [ "$PF_ENABLED" = "true" ]; then
  curl --connect-timeout 2 --max-time 4 -sSf http://localhost:12009/health || true
else
  kubectl --context "$KCTX" -n "$NS" run curl-$$ --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
    curl -sSf http://$APP.$NS.svc.cluster.local:12009/health || true
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
      curl -sS -c \$CJ -H 'Content-Type: application/json' -H \"Host: \$HOST\" -d '{\"email\":\"admin@example.com\",\"password\":\"change-me\",\"name\":\"Admin\"}' http://$APP.$NS.svc.cluster.local:12009/api/auth/sign-up/email >/dev/null || true; \
      curl -sS -c \$CJ -H 'Content-Type: application/json' -H \"Host: \$HOST\" -d '{\"email\":\"admin@example.com\",\"password\":\"change-me\"}' http://$APP.$NS.svc.cluster.local:12009/api/auth/sign-in/email >/dev/null; \
      curl -sS -b \$CJ -H \"Host: \$HOST\" 'http://$APP.$NS.svc.cluster.local:12009/trpc/frontend/frontend.mcpServers.list?input=%7B%7D' || true"
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
echo "# Final logs"
kubectl --context "$KCTX" -n "$NS" logs deploy/$APP --tail=200 || true
kubectl --context "$KCTX" -n "$NS" logs job/$APP-provision --tail=200 || true
kubectl --context "$KCTX" -n "$NS" logs job/$APP-user-bootstrap --tail=200 || true
echo "# Server pod logs"
kubectl --context "$KCTX" -n "$NS" logs -l app.kubernetes.io/component=server --tail=120 || true
echo "# Done"
