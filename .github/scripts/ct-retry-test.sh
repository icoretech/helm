#!/usr/bin/env bash
#
# Contract test for ct-retry.sh.
#
# The case that matters is "always fails": the inline loop this helper replaces
# exited 0 there, so chart-testing could not fail a pull request.
#
# Whether the workflow still *calls* the helper, unguarded, is a different
# question and a different guard: `verify-ci-gate.py` parses the workflow rather
# than grepping it, because every interesting way of turning the gate off is
# invisible to a grep.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
retry="${here}/ct-retry.sh"
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

# A non-positive budget skipped the loop and exited 0 without running anything.
for bad_attempts in 0 -1 abc; do
  dir="$(mktemp -d)"
  make_command "$dir" 0 0
  status=0
  CT_RETRY_BACKOFF_SECONDS=0 CT_RETRY_ATTEMPTS="$bad_attempts" \
    "$retry" "${dir}/fake" >/dev/null 2>&1 || status=$?
  assert_eq "CT_RETRY_ATTEMPTS='${bad_attempts}' is a usage error" 2 "$status"
  assert_eq "CT_RETRY_ATTEMPTS='${bad_attempts}' runs nothing" 0 "$(calls_of "$dir")"
  rm -rf "$dir"
done

status=0
CT_RETRY_BACKOFF_SECONDS=abc "$retry" /usr/bin/true >/dev/null 2>&1 || status=$?
assert_eq "a non-numeric backoff is a usage error" 2 "$status"

# The other end of the range: a budget nothing bounds burns the runner to the
# six-hour job limit and buries the failure it was retrying.
for huge in 11 9223372036854775807 99999999999999999999; do
  status=0
  CT_RETRY_BACKOFF_SECONDS=0 CT_RETRY_ATTEMPTS="$huge" \
    "$retry" /usr/bin/false >/dev/null 2>&1 || status=$?
  assert_eq "CT_RETRY_ATTEMPTS='${huge}' is refused" 2 "$status"
done

status=0
CT_RETRY_ATTEMPTS=1 CT_RETRY_BACKOFF_SECONDS=99999999999999999999 \
  "$retry" /usr/bin/true >/dev/null 2>&1 || status=$?
assert_eq "an unbounded backoff is refused" 2 "$status"

# An empty value is an unset value: it must reach the default budget, not the
# refusal above.
dir="$(mktemp -d)"
make_command "$dir" 2 7
status=0
CT_RETRY_BACKOFF_SECONDS=0 CT_RETRY_ATTEMPTS='' \
  "$retry" "${dir}/fake" >/dev/null 2>&1 || status=$?
assert_eq "an empty CT_RETRY_ATTEMPTS uses the default budget" 0 "$status"
assert_eq "an empty CT_RETRY_ATTEMPTS keeps three attempts" 3 "$(calls_of "$dir")"
rm -rf "$dir"

if [[ "$failures" -ne 0 ]]; then
  echo "${failures} assertion(s) failed" >&2
  exit 1
fi
echo "all assertions passed"
