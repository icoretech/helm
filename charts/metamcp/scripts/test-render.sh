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
