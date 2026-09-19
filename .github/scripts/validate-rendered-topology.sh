#!/usr/bin/env bash
#
# Sends a chart's real topology to the API server for validation.
#
# This runs in addition to `ct install`, not instead of it. `ct install` starts
# the real workloads against the fixtures in `ci/fixtures/`, which is the only
# thing that sees ordering — hook phases, readiness, a Secret that does not
# exist yet. This step sees what a running install cannot report cheaply: every
# object checked by the API server's own validation, including the ones a
# release would never reach because it failed earlier.
#
# A chart opts in by committing `tests/server-dry-run-values.yaml`. The rendered
# manifests go to `kubectl apply --dry-run=server`, which validates them against
# the real API server — apiVersions, unknown or mistyped fields, required
# fields, name and port-name syntax, label values — without creating anything
# and without needing a pod to start. The API server resolves some admission
# references even during a server dry-run: a standalone Pod's service account
# must already exist. Each chart therefore gets a disposable namespace and its
# rendered ServiceAccount prerequisite is applied before the full dry-run. A
# Service pointing at a port no container exposes is still valid to the API
# server, which is why those relationships live in the chart's unit tests.
#
# Usage: validate-rendered-topology.sh <chart-dir>...
set -uo pipefail

values_file="tests/server-dry-run-values.yaml"
status=0
rendered_files=()
owned_namespaces=()

cleanup() {
  local rendered namespace
  for rendered in "${rendered_files[@]}"; do
    rm -f "$rendered"
  done
  for namespace in "${owned_namespaces[@]}"; do
    kubectl delete namespace "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  done
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for chart in "$@"; do
  [[ -n "$chart" ]] || continue

  if [[ ! -f "${chart}/${values_file}" ]]; then
    echo "::notice::skipping ${chart} (no ${values_file})"
    continue
  fi

  if [[ -n "${TOPOLOGY_DRY_RUN_NAMESPACE:-}" ]]; then
    namespace="$TOPOLOGY_DRY_RUN_NAMESPACE"
  else
    chart_name="$(basename "$chart" | tr -cs 'a-z0-9-' '-')"
    namespace="topology-${chart_name}-${GITHUB_RUN_ID:-$$}"
    namespace="${namespace:0:63}"
    kubectl create namespace "$namespace" >/dev/null
    owned_namespaces+=("$namespace")
  fi

  echo "==> rendering ${chart} with ${values_file}"
  rendered="$(mktemp)"
  rendered_files+=("$rendered")
  # The render contains the chart's Secret in cleartext; do not leave it behind
  # if the run is interrupted between here and the EXIT cleanup.
  if ! helm template topology "$chart" \
    --namespace "$namespace" \
    --values "${chart}/${values_file}" >"$rendered"; then
    echo "::error::helm template failed for ${chart}"
    status=1
    rm -f "$rendered"
    continue
  fi

  if [[ -f "${chart}/templates/serviceaccount.yaml" ]]; then
    echo "==> creating ${chart} ServiceAccount prerequisite in ${namespace}"
    if ! helm template topology "$chart" \
      --namespace "$namespace" \
      --values "${chart}/${values_file}" \
      --show-only templates/serviceaccount.yaml |
      kubectl apply --namespace "$namespace" -f -; then
      echo "::error::failed to create the rendered ServiceAccount prerequisite for ${chart}"
      status=1
      rm -f "$rendered"
      continue
    fi
  fi

  echo "==> validating ${chart} against the API server"
  if ! kubectl apply --dry-run=server --namespace "$namespace" -f "$rendered"; then
    echo "::error::the rendered topology of ${chart} is not accepted by the API server"
    status=1
  fi
  rm -f "$rendered"
done

cleanup
trap - EXIT
exit "$status"
