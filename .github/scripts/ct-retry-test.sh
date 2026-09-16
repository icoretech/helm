#!/usr/bin/env bash
#
# Contract test for ct-retry.sh and for the workflow steps that must use it.
#
# The case that matters is "always fails": the inline loop this helper replaces
# exited 0 there, so chart-testing could not fail a pull request.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
retry="${here}/ct-retry.sh"
workflow="${here}/../workflows/test.yml"
failures=0

pass() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1" >&2
  failures=$((failures + 1))
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "${label} (${actual})"
  else
    fail "${label}: expected ${expected}, got ${actual}"
  fi
}

# Builds a fake command that fails `fail_times` times with `code`, then succeeds.
make_command() {
  local dir="$1" fail_times="$2" code="$3"
  printf '0\n' >"${dir}/calls"
  cat >"${dir}/fake" <<FAKE
#!/usr/bin/env bash
calls=\$(< "${dir}/calls")
calls=\$((calls + 1))
printf '%s\n' "\$calls" > "${dir}/calls"
if [[ "\$calls" -le ${fail_times} ]]; then
  exit ${code}
fi
exit 0
FAKE
  chmod +x "${dir}/fake"
}

calls_of() { cat "$1/calls"; }

run_case() {
  local label="$1" fail_times="$2" code="$3" want_status="$4" want_calls="$5"
  local dir
  dir="$(mktemp -d)"
  make_command "$dir" "$fail_times" "$code"

  local status=0
  CT_RETRY_BACKOFF_SECONDS=0 "$retry" "${dir}/fake" >/dev/null 2>&1 || status=$?

  assert_eq "${label}: exit status" "$want_status" "$status"
  assert_eq "${label}: invocations" "$want_calls" "$(calls_of "$dir")"
  rm -rf "$dir"
}

echo "== ct-retry.sh behaviour =="
run_case "succeeds immediately" 0 0 0 1
run_case "succeeds on the third attempt" 2 7 0 3
# The regression: a command that never succeeds MUST fail the step.
run_case "always fails, propagates exit 7" 9 7 7 3
run_case "always fails, propagates exit 3" 9 3 3 3

status=0
CT_RETRY_BACKOFF_SECONDS=0 CT_RETRY_ATTEMPTS=1 "$retry" /usr/bin/false >/dev/null 2>&1 || status=$?
assert_eq "single attempt still fails" 1 "$status"

status=0
"$retry" >/dev/null 2>&1 || status=$?
assert_eq "missing command is a usage error" 2 "$status"

echo "== workflow wiring =="
# The helper only protects the workflow while the workflow actually calls it.
for step in lint install; do
  if grep -qE "ct-retry\.sh ct ${step}\b" "$workflow"; then
    pass "ct ${step} runs through ct-retry.sh"
  else
    fail "ct ${step} does not run through ct-retry.sh"
  fi
done

# `rc=$?` after a `fi` reads the `if` compound status, not the command's.
if awk '/^[[:space:]]*fi[[:space:]]*$/ { prev_fi = 1; next }
        /^[[:space:]]*rc=\$\?[[:space:]]*$/ { if (prev_fi) { found = 1 } }
        { prev_fi = 0 }
        END { exit found ? 0 : 1 }' "$workflow"; then
  fail "workflow still reads rc=\$? after a conditional"
else
  pass "workflow never reads rc=\$? after a conditional"
fi

if [[ "$failures" -ne 0 ]]; then
  echo "${failures} assertion(s) failed" >&2
  exit 1
fi
echo "all assertions passed"
