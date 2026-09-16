#!/usr/bin/env bash
#
# Sends a chart's real topology to the API server for validation.
#
# `ci/install-values.yaml` is what `ct install` uses, and it has to stay
# installable in a kind cluster with no database, no secrets and no published
# application image. For codex-pooler that means app, migrations, worker and
# scheduler are all disabled there, so `ct lint` and `ct install` only ever see
# a ServiceAccount: a template change that broke every workload would pass both.
#
# A chart opts into this check by committing `tests/server-dry-run-values.yaml`.
# The rendered manifests go to `kubectl apply --dry-run=server`, which validates
# them against the real API server — apiVersions, unknown or mistyped fields,
# required fields, name and port-name syntax, label values — without creating
# anything and without needing a pod to start.
#
# Usage: validate-rendered-topology.sh <chart-dir>...
set -uo pipefail

values_file="tests/server-dry-run-values.yaml"
namespace="${TOPOLOGY_DRY_RUN_NAMESPACE:-default}"
status=0

for chart in "$@"; do
  [[ -n "$chart" ]] || continue

  if [[ ! -f "${chart}/${values_file}" ]]; then
    echo "::notice::skipping ${chart} (no ${values_file})"
    continue
  fi

  echo "==> rendering ${chart} with ${values_file}"
  rendered="$(mktemp)"
  if ! helm template topology "$chart" \
    --namespace "$namespace" \
    --values "${chart}/${values_file}" >"$rendered"; then
    echo "::error::helm template failed for ${chart}"
    status=1
    rm -f "$rendered"
    continue
  fi

  echo "==> validating ${chart} against the API server"
  if ! kubectl apply --dry-run=server --namespace "$namespace" -f "$rendered"; then
    echo "::error::the rendered topology of ${chart} is not accepted by the API server"
    status=1
  fi
  rm -f "$rendered"
done

exit "$status"
