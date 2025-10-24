#!/usr/bin/env bash
set -euo pipefail
NS=${NS:-metamcp}
REL=${REL:-metamcp}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

echo "# Installing $REL in $NS"
helm upgrade --install "$REL" "$ROOT" -n "$NS" --create-namespace -f "$ROOT/examples/e2e.yaml" --wait --timeout 60s \
  --set auth.betterAuthSecret=dev-secret \
  --set env.APP_URL="http://$REL-$REL.$NS.svc.cluster.local:12008"

echo "# Pods"
kubectl -n "$NS" get pods -o wide

echo "# Tail important logs (metamcp, provision, user-bootstrap)"
kubectl -n "$NS" logs deploy/$REL-$REL --tail=200 || true
kubectl -n "$NS" logs job/$REL-$REL-provision --tail=200 || true
kubectl -n "$NS" logs job/$REL-$REL-user-bootstrap --tail=200 || true

echo "# Port-forward service"
kubectl -n "$NS" port-forward svc/$REL-$REL 12008:12008 12009:12009 >/tmp/${REL}.pf.log 2>&1 &
PF=$!
sleep 2

HOST="$REL-$REL.$NS.svc.cluster.local"
echo "# Backend health"
curl -sSf http://localhost:12009/health | jq .

echo "# Authenticate and verify resources"
CJ=/tmp/${REL}.cookies.txt
rm -f "$CJ"
curl -sS -c "$CJ" -H "Content-Type: application/json" -H "Host: $HOST" \
  -d '{"email":"admin@example.com","password":"change-me","name":"Admin"}' \
  http://localhost:12009/api/auth/sign-up/email >/dev/null || true
curl -sS -c "$CJ" -H "Content-Type: application/json" -H "Host: $HOST" \
  -d '{"email":"admin@example.com","password":"change-me"}' \
  http://localhost:12009/api/auth/sign-in/email >/dev/null

echo "# tRPC: list servers/namespaces/endpoints"
curl -sS -b "$CJ" -H "Host: $HOST" \
  "http://localhost:12009/trpc/frontend/frontend.mcpServers.list?input=%7B%7D" | jq -r '.result.data.data[].name' || true
curl -sS -b "$CJ" -H "Host: $HOST" \
  "http://localhost:12009/trpc/frontend/frontend.namespaces.list?input=%7B%7D" | jq -r '.result.data.data[].name' || true
curl -sS -b "$CJ" -H "Host: $HOST" \
  "http://localhost:12009/trpc/frontend/frontend.endpoints.list?input=%7B%7D" | jq -r '.result.data.data[].name' || true

kill $PF >/dev/null 2>&1 || true
echo "# Done"

