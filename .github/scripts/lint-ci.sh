#!/usr/bin/env bash
#
# Lints the CI definition itself.
#
# Every guard in `.github/scripts/` is only worth what the workflow and the
# scripts around it are, and nothing in this repository used to check either:
# `actionlint` and `shellcheck` were run by hand, if at all. This step runs them
# on every pull request, chart change or not.
#
# Both tools are pinned and run from their images when the binary is absent, so
# a runner image change cannot silently downgrade what is enforced.
set -uo pipefail

actionlint_version="1.7.12"
shellcheck_version="0.11.0"
status=0

run_tool() {
  local binary="$1" version="$2" image="$3"
  shift 3

  # Match the pinned version exactly, not as a substring: 1.7.121 is not 1.7.12.
  local pattern="(^|[^0-9.])${version//./\\.}([^0-9.]|$)"
  if command -v "$binary" >/dev/null 2>&1 &&
    "$binary" --version 2>/dev/null | head -3 | grep -qE "$pattern"; then
    "$binary" "$@"
    return
  fi

  docker run --rm --volume "$PWD:/repo" --workdir /repo "$image" "$@"
}

echo "==> actionlint"
if ! run_tool actionlint "$actionlint_version" "rhysd/actionlint:${actionlint_version}" -color; then
  echo "::error::actionlint failed"
  status=1
fi

echo "==> shellcheck"
shopt -s nullglob
scripts=(.github/scripts/*.sh charts/*/scripts/*.sh)
if ! run_tool shellcheck "$shellcheck_version" "koalaman/shellcheck:v${shellcheck_version}" "${scripts[@]}"; then
  echo "::error::shellcheck failed"
  status=1
fi

echo "==> python syntax"
while IFS= read -r script; do
  [[ -n "$script" ]] || continue
  if ! python3 -m py_compile "$script"; then
    echo "::error::${script} does not compile"
    status=1
  fi
done < <(find .github/scripts -name '*.py' -type f)

exit "$status"
