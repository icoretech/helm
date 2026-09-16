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
# and without needing a pod to start. It resolves no reference between objects:
# a Service pointing at a port no container exposes is valid to it, which is why
# those live in the chart's unit tests.
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
  # The render contains the chart's Secret in cleartext; do not leave it behind
  # if the run is interrupted between here and the cleanup below.
  # `exit` on a signal as well: cleaning up and then carrying on would validate
  # a file that no longer exists and report it as a chart failure.
  trap 'rm -f "$rendered"' EXIT
  trap 'rm -f "$rendered"; exit 130' INT
  trap 'rm -f "$rendered"; exit 143' TERM
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
