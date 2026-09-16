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
# Usage: assert-no-chart-changed.sh <target-branch> [remote] [chart-dir]
set -uo pipefail

target_branch="${1:-main}"
remote="${2:-origin}"
chart_dir="${3:-charts}"
base="${remote}/${target_branch}"

if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  echo "::error::cannot resolve ${base}, so an empty chart list cannot be trusted" >&2
  exit 1
fi

merge_base="$(git merge-base "$base" HEAD)" || {
  echo "::error::cannot find a merge base with ${base}" >&2
  exit 1
}

# `git diff` over a pathspec that matches nothing exits 0, so a wrong chart
# directory would report agreement it never checked. This check exists because
# chart-testing's empty answer is not to be trusted; its own input is not
# either.
if ! compgen -G "${chart_dir}/*/Chart.yaml" >/dev/null; then
  echo "::error::no chart found under ${chart_dir}; this check cannot verify an empty chart list" >&2
  exit 1
fi

changed_charts=()
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  chart="${path%%/*}/"
  rest="${path#*/}"
  chart="${chart}${rest%%/*}"
  # A chart deleted by this pull request has nothing left to lint or install.
  git cat-file -e "HEAD:${chart}/Chart.yaml" 2>/dev/null || continue
  changed_charts+=("$chart")
done < <(git diff --name-only "$merge_base" HEAD -- "${chart_dir}/*/*" | sort -u)

if [[ "${#changed_charts[@]}" -gt 0 ]]; then
  readarray -t changed_charts < <(printf '%s\n' "${changed_charts[@]}" | sort -u)
  echo "::error::ct list-changed reported no changed charts, but this pull request changes:" >&2
  printf '  %s\n' "${changed_charts[@]}" >&2
  echo "Chart change detection is broken; the lint, unittest and install steps would all have skipped." >&2
  exit 1
fi

echo "No chart changed, and the diff against ${base} agrees."
