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

if ! rg -q '"headersFrom":\[\{"secretRef":\{"name":"metamcp-icoretech-airbroke-headers"\}\}\]' "$OUT"; then
  echo "expected provision.json to preserve headersFrom secret refs for remote servers" >&2
  sed -n '1,220p' "$OUT" >&2
  exit 1
fi
