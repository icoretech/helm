#!/usr/bin/env bash
#
# Fails when a chart's committed README.md is not what helm-docs generates.
#
# Chart READMEs are generated from README.md.gotmpl, but the only thing that
# ever runs helm-docs is `sync-gh-pages.yml`, which regenerates them to publish
# into the gh-pages branch and never commits the result back. So every chart
# version bump or values change leaves the tracked README stale until somebody
# notices by hand — and the published docs silently disagree with the branch.
# This check puts the regeneration in the pull request that causes the drift.
#
# The helm-docs version is pinned to the one sync-gh-pages.yml publishes with,
# so the two cannot produce different output.
#
# Usage: check-chart-docs.sh <chart-dir>...
set -uo pipefail

helm_docs_version="1.14.2"
helm_docs_image="${HELM_DOCS_IMAGE:-jnorwood/helm-docs:v${helm_docs_version}}"
chart_root="${CHART_SEARCH_ROOT:-charts}"
status=0

run_helm_docs() {
  local chart="$1"

  if command -v helm-docs >/dev/null 2>&1 &&
    helm-docs --version 2>/dev/null | grep -qF "$helm_docs_version"; then
    helm-docs --chart-search-root="$chart_root" \
      --chart-to-generate="$chart" \
      --output-file README.md
    return
  fi

  docker run --rm \
    --volume "$PWD:/helm-docs" \
    -u "$(id -u):$(id -g)" \
    "$helm_docs_image" \
    --chart-search-root="$chart_root" \
    --chart-to-generate="$chart" \
    --output-file README.md
}

for chart in "$@"; do
  [[ -n "$chart" ]] || continue

  if [[ ! -f "${chart}/README.md.gotmpl" ]]; then
    echo "::notice::skipping ${chart} (no README.md.gotmpl)"
    continue
  fi

  echo "==> regenerating ${chart}/README.md"
  if ! run_helm_docs "$chart"; then
    echo "::error::helm-docs failed for ${chart}"
    status=1
    continue
  fi

  if ! git diff --exit-code -- "${chart}/README.md"; then
    echo "::error::${chart}/README.md is out of date; regenerate it with helm-docs v${helm_docs_version} and commit the result" >&2
    status=1
  fi
done

exit "$status"
