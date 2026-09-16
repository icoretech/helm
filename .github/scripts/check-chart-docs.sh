#!/usr/bin/env bash
#
# Fails when a chart's committed documentation is not what helm-docs generates.
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
# Note: `helm-docs` with a stray positional argument regenerates every chart
# README under the working directory, without asking. Keep the invocation below
# flag-only.
#
# Usage: check-chart-docs.sh <chart-dir>...
set -uo pipefail

helm_docs_version="1.14.2"
helm_docs_image="jnorwood/helm-docs:v${helm_docs_version}"
# Deliberately not configurable: an env override of the search root makes
# helm-docs skip the chart, exit 0, and the check pass on a stale README.
chart_root="charts"
status=0

run_helm_docs() {
  local chart="$1" output_file="$2"

  if command -v helm-docs >/dev/null 2>&1 &&
    [[ "$(helm-docs --version 2>/dev/null | awk '{print $3}')" == "$helm_docs_version" ]]; then
    helm-docs --chart-search-root="$chart_root" \
      --chart-to-generate="$chart" \
      --output-file "$output_file"
    return
  fi

  docker run --rm \
    --volume "$PWD:/helm-docs" \
    -u "$(id -u):$(id -g)" \
    "$helm_docs_image" \
    --chart-search-root="$chart_root" \
    --chart-to-generate="$chart" \
    --output-file "$output_file"
}

# The tracked documentation file, so the generated one lands on the path git
# actually watches. `git diff --exit-code -- <path>` is silent for an untracked
# path, so generating README.md next to a tracked Readme.md would always pass.
tracked_doc() {
  local chart="$1" candidate
  for candidate in README.md Readme.md; do
    if git ls-files --error-unmatch "${chart}/${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf '%s\n' README.md
}

for chart in "$@"; do
  [[ -n "$chart" ]] || continue

  if [[ ! -f "${chart}/README.md.gotmpl" ]]; then
    echo "::notice::skipping ${chart} (no README.md.gotmpl)"
    continue
  fi

  output_file="$(tracked_doc "$chart")"
  echo "==> regenerating ${chart}/${output_file}"
  if ! run_helm_docs "$chart" "$output_file"; then
    echo "::error::helm-docs failed for ${chart}"
    status=1
    continue
  fi

  if [[ ! -s "${chart}/${output_file}" ]]; then
    echo "::error::helm-docs generated nothing for ${chart}" >&2
    status=1
    continue
  fi

  # `git status` rather than `git diff`, so a generated file that is not tracked
  # at all counts as drift instead of silence.
  if [[ -n "$(git status --porcelain -- "${chart}/${output_file}")" ]]; then
    git --no-pager diff -- "${chart}/${output_file}"
    git status --porcelain -- "${chart}/${output_file}"
    echo "::error::${chart} documentation is out of date; regenerate it with helm-docs v${helm_docs_version} and commit the result" >&2
    status=1
  fi
done

exit "$status"
