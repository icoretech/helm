#!/usr/bin/env bash
#
# Cross-checks an empty `ct list-changed` against the pull request's own diff.
#
# When `ct list-changed` prints nothing, every validation step in the workflow
# skips and the required check still passes. That is correct for a pull request
# that touches no chart, and it is silent breakage when the detection itself is
# wrong: a bad target branch, a checkout without history, a chart-testing
# version or config change. So when chart-testing reports nothing, require git
# to agree that nothing under a chart changed.
#
# The chart directory is not a parameter. This check exists because
# chart-testing's empty answer is not to be trusted, and a check that takes its
# own notion of where charts live from its caller can be pointed at an empty or
# unrelated directory and report agreement it never established.
#
# Usage: assert-no-chart-changed.sh <target-branch> [remote]
set -uo pipefail

target_branch="${1:-main}"
remote="${2:-origin}"
chart_dir="charts"
base="${remote}/${target_branch}"

# Everything below assumes chart-testing's defaults: charts live in `charts/`
# and none is excluded. A configuration file can change both, in which case the
# two sides stop meaning the same thing and this check has to be updated with it.
for config in ct.yaml .ct.yaml "${HOME}/.ct/ct.yaml" /etc/ct/ct.yaml; do
  if [[ -e "$config" ]]; then
    echo "::error::${config} can change chart-dirs or excluded-charts; this cross-check assumes chart-testing's defaults and must be updated with it" >&2
    exit 1
  fi
done

if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  echo "::error::cannot resolve ${base}, so an empty chart list cannot be trusted" >&2
  exit 1
fi

merge_base="$(git merge-base "$base" HEAD)" || {
  echo "::error::cannot find a merge base with ${base}" >&2
  exit 1
}

if ! compgen -G "${chart_dir}/*/Chart.yaml" >/dev/null; then
  echo "::error::no chart found under ${chart_dir}; this check cannot verify an empty chart list" >&2
  exit 1
fi

changed_charts=()
unverifiable=()
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  rest="${path#"${chart_dir}/"}"
  if [[ "$rest" != */* ]]; then
    # An entry directly under charts/ that is not a file inside a chart. A
    # symlinked chart directory looks exactly like this, and `charts/*/*` would
    # never match anything inside it.
    if [[ -L "${chart_dir}/${rest}" || -d "${chart_dir}/${rest}" ]]; then
      unverifiable+=("$path")
    fi
    continue
  fi
  chart="${chart_dir}/${rest%%/*}"
  # A chart deleted by this pull request has nothing left to lint or install.
  git cat-file -e "HEAD:${chart}/Chart.yaml" 2>/dev/null || continue
  changed_charts+=("$chart")
done < <(git diff --name-only "$merge_base" HEAD -- "$chart_dir" | sort -u)

if [[ "${#changed_charts[@]}" -gt 0 ]]; then
  readarray -t changed_charts < <(printf '%s\n' "${changed_charts[@]}" | sort -u)
  echo "::error::ct list-changed reported no changed charts, but this pull request changes:" >&2
  printf '  %s\n' "${changed_charts[@]}" >&2
  echo "Chart change detection is broken; the lint, unittest and install steps would all have skipped." >&2
  exit 1
fi

if [[ "${#unverifiable[@]}" -gt 0 ]]; then
  echo "::error::this pull request changes entries under ${chart_dir}/ that are not files inside a chart:" >&2
  printf '  %s\n' "${unverifiable[@]}" >&2
  echo "A symlinked chart directory is invisible to both chart-testing and this check." >&2
  exit 1
fi

echo "No chart changed, and the diff against ${base} agrees."
