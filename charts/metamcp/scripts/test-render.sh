#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHART="$ROOT"
OUT=/tmp/metamcp-render.yaml

helm template t "$CHART" -f "$ROOT/ci/prune-valid-values.yaml" >"$OUT"

if ! rg -q 'name: PRUNE' "$OUT"; then
  echo "expected provision job to receive PRUNE env when provision.prune=true" >&2
  sed -n '1,220p' "$OUT" >&2
  exit 1
fi

helm template t "$CHART" -f "$ROOT/ci/headersfrom-values.yaml" >"$OUT"

if ! rg -q '"headersFrom":\[\{"secretRef":\{"name":"metamcp-remote-headers"\}\}\]' "$OUT"; then
  echo "expected provision.json to preserve headersFrom secret refs for remote servers" >&2
  sed -n '1,220p' "$OUT" >&2
  exit 1
fi

helm template t "$CHART" -f "$ROOT/ci/urlfrom-values.yaml" >"$OUT"

if ! rg -q '"urlFrom":\[\{"secretRef":\{"name":"metamcp-remote-url"\}\}\]' "$OUT"; then
  echo "expected provision.json to preserve urlFrom secret refs for remote servers" >&2
  sed -n '1,220p' "$OUT" >&2
  exit 1
fi

helm template t "$CHART" -f "$ROOT/ci/namespace-server-active-values.yaml" >"$OUT"

if ! rg -q '"active":false,"name":"billing-sandbox"' "$OUT"; then
  echo "expected provision.json to preserve namespace server objects with active=false" >&2
  sed -n '1,220p' "$OUT" >&2
  exit 1
fi

if ! rg -q '"billing-production"' "$OUT"; then
  echo "expected provision.json to preserve namespace server objects with active=false" >&2
  sed -n '1,220p' "$OUT" >&2
  exit 1
fi

helm template t "$CHART" --show-only templates/ingress.yaml \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=metamcp.example.com \
  --set ingress.localePrefixes[0]=de >"$OUT"

if ! rg -F -q 'nginx.ingress.kubernetes.io/configuration-snippet' "$OUT"; then
  echo "expected nginx ingress to receive tRPC rewrite snippet" >&2
  exit 1
fi

if ! rg -F -q 'rewrite ^/de/trpc/(frontend\..*) /de/trpc/frontend/$1 break;' "$OUT"; then
  echo "expected nginx ingress to rewrite configured locale tRPC short path" >&2
  exit 1
fi

helm template t "$CHART" --show-only templates/ingress.yaml \
  --set ingress.enabled=true \
  --set ingress.className=traefik \
  --set ingress.hosts[0].host=metamcp.example.com >"$OUT"

if rg -F -q 'trpc-short-path-rewrite' "$OUT"; then
  echo "expected traefik rewrite to stay disabled when traefik.io Middleware API is unavailable" >&2
  exit 1
fi

helm template t "$CHART" --api-versions traefik.containo.us/v1alpha1/Middleware --show-only templates/ingress.yaml \
  --set ingress.enabled=true \
  --set ingress.className=traefik \
  --set ingress.hosts[0].host=metamcp.example.com >"$OUT"

if rg -F -q 'trpc-short-path-rewrite' "$OUT"; then
  echo "expected traefik rewrite to ignore legacy traefik.containo.us Middleware API" >&2
  exit 1
fi


helm template t "$CHART" --api-versions traefik.io/v1alpha1/Middleware --show-only templates/ingress.yaml --show-only templates/traefik-middleware.yaml \
  --set ingress.enabled=true \
  --set ingress.className=traefik \
  --set ingress.hosts[0].host=metamcp.example.com \
  --set ingress.localePrefixes[0]=de >"$OUT"

if ! rg -F -q 'kind: Middleware' "$OUT"; then
  echo "expected traefik ingress to render tRPC rewrite middleware" >&2
  exit 1
fi

if ! rg -F -q 'traefik.ingress.kubernetes.io/router.middlewares: default-t-metamcp-trpc-short-path-rewrite@kubernetescrd' "$OUT"; then
  echo "expected traefik ingress to reference generated middleware" >&2
  exit 1
fi

if ! rg -F -q 'regex: "^(/(?:de))?/trpc/(frontend\\..*)$"' "$OUT"; then
  echo "expected traefik middleware to preserve locale prefix capture" >&2
  exit 1
fi

if ! rg -F -q 'replacement: "$1/trpc/frontend/$2"' "$OUT"; then
  echo "expected traefik middleware to expand backend tRPC path" >&2
  exit 1
fi

helm template t "$CHART" --api-versions traefik.io/v1alpha1/Middleware --show-only templates/ingress.yaml \
  --set ingress.enabled=true \
  --set ingress.className=traefik \
  --set ingress.hosts[0].host=metamcp.example.com \
  --set-string 'ingress.annotations.traefik\.ingress\.kubernetes\.io/router\.middlewares=auth@kubernetescrd' >"$OUT"

if ! rg -F -q 'traefik.ingress.kubernetes.io/router.middlewares: default-t-metamcp-trpc-short-path-rewrite@kubernetescrd,auth@kubernetescrd' "$OUT"; then
  echo "expected traefik ingress to preserve existing middlewares" >&2
  exit 1
fi

helm template t "$CHART" --api-versions traefik.io/v1alpha1/Middleware --show-only templates/ingress.yaml --show-only templates/traefik-middleware.yaml \
  --set ingress.enabled=true \
  --set ingress.className=traefik-public \
  --set ingress.hosts[0].host=metamcp.example.com \
  --set ingress.rewriteTrpcShortPathController=traefik >"$OUT"

if ! rg -F -q 'traefik.ingress.kubernetes.io/router.middlewares: default-t-metamcp-trpc-short-path-rewrite@kubernetescrd' "$OUT"; then
  echo "expected explicit traefik rewrite controller to ignore custom IngressClass names" >&2
  exit 1
fi

helm template t "$CHART" --api-versions traefik.io/v1alpha1/Middleware \
  --set ingress.enabled=true \
  --set ingress.className=traefik \
  --set ingress.hosts[0].host=metamcp.example.com \
  --set ingress.rewriteTrpcShortPath=false >"$OUT"

if rg -F -q 'trpc-short-path-rewrite' "$OUT"; then
  echo "expected rewriteTrpcShortPath=false to suppress generated rewrite middleware" >&2
  exit 1
fi
