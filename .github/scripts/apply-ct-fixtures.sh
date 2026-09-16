#!/usr/bin/env bash
#
# Applies the cluster fixtures a chart needs before `ct install` runs.
#
# chart-testing can only install the chart under test, so a chart whose release
# cannot boot without an external dependency — codex-pooler needs a reachable
# PostgreSQL — otherwise has to disable its own workloads in
# `ci/install-values.yaml`, which leaves `ct install` validating almost nothing.
#
# A chart opts in by committing manifests under `ci/fixtures/`. They are applied
# into the throwaway CI cluster only; they are never part of the chart's
# rendered output (`ci/` is excluded from the package by `.helmignore`).
#
# This script MUTATES the cluster its kubeconfig points at — it is the only
# script under `.github/scripts/` that does — so it refuses any context that is
# not a kind cluster. Set CT_FIXTURE_ALLOW_CONTEXT to the context name to
# override that deliberately.
#
# Usage: apply-ct-fixtures.sh <chart-dir>...
set -uo pipefail

fixture_dir="ci/fixtures"
fixture_label="helm.icoretech.io/ct-fixture=true"
timeout="${CT_FIXTURE_TIMEOUT:-300s}"
applied=0
status=0

context="$(kubectl config current-context 2>/dev/null)" || context=""
allowed="${CT_FIXTURE_ALLOW_CONTEXT:-}"
if [[ -z "$context" ]]; then
  echo "::error::no current kubectl context; refusing to guess where to apply cluster fixtures" >&2
  exit 1
fi
if [[ "$context" != kind-* && "$context" != "$allowed" ]]; then
  echo "::error::refusing to apply cluster fixtures to context '${context}': it is not a kind cluster" >&2
  echo "Set CT_FIXTURE_ALLOW_CONTEXT='${context}' if that is really what you want." >&2
  exit 1
fi
echo "==> applying ct fixtures to context ${context}"

for chart in "$@"; do
  [[ -n "$chart" ]] || continue

  if [[ ! -d "${chart}/${fixture_dir}" ]]; then
    echo "::notice::skipping ${chart} (no ${fixture_dir})"
    continue
  fi

  echo "==> applying ${chart}/${fixture_dir}"
  if ! kubectl apply -f "${chart}/${fixture_dir}"; then
    echo "::error::could not apply the ct fixtures of ${chart}"
    status=1
    continue
  fi
  applied=$((applied + 1))
done

[[ "$applied" -gt 0 ]] || exit "$status"

# Every fixture namespace carries the label, so one wait covers all charts.
namespaces="$(kubectl get namespace --selector "$fixture_label" --output name)"
if [[ -z "$namespaces" ]]; then
  echo "::error::fixtures were applied but no namespace carries ${fixture_label}" >&2
  exit 1
fi

while IFS= read -r namespace; do
  [[ -n "$namespace" ]] || continue
  namespace="${namespace#namespace/}"
  # `kubectl wait --for=condition=Available` is satisfied while an older
  # replica set is still serving, which would let chart-testing install against
  # a database pod that is about to be replaced. Wait for the rollout instead.
  while IFS= read -r deployment; do
    [[ -n "$deployment" ]] || continue
    echo "==> waiting for ${deployment} in ${namespace}"
    if ! kubectl rollout status "$deployment" \
      --namespace "$namespace" --timeout "$timeout"; then
      echo "::error::the ct fixture ${deployment} in ${namespace} never rolled out"
      kubectl get pods --namespace "$namespace" -o wide || true
      status=1
    fi
  done < <(kubectl get deployment --namespace "$namespace" --output name)
done <<<"$namespaces"

exit "$status"
