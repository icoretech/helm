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

# Prints the `run:` body of the step whose `- name:` is exactly $2.
# Handles both the block form (`run: |`) and the one-line form.
step_run_body() {
  awk -v want="$2" '
    /^      - / { instep = (substr($0, 9) == "name: " want); inrun = 0; next }
    !instep { next }
    /^        run:[[:space:]]*[|>]/ { inrun = 1; next }
    /^        run:[[:space:]]/ { sub(/^        run:[[:space:]]*/, ""); print; next }
    /^        [A-Za-z][A-Za-z0-9_-]*:/ { inrun = 0; next }
    inrun { print }
  ' "$1"
}

# Prints the keys declared on the step whose `- name:` is exactly $2.
step_keys() {
  awk -v want="$2" '
    /^      - / { instep = (substr($0, 9) == "name: " want); next }
    !instep { next }
    /^        [A-Za-z][A-Za-z0-9_-]*:/ { key = $1; sub(/:.*/, "", key); print key }
  ' "$1"
}

# Collapses a run body into its logical commands: backslash continuations are
# joined, comments and blank lines dropped, whitespace normalised.
logical_commands() {
  awk '
    { line = line $0
      if (line ~ /\\$/) { sub(/\\$/, " ", line); next }
      gsub(/^[[:space:]]+/, "", line); gsub(/[[:space:]]+/, " ", line)
      gsub(/[[:space:]]+$/, "", line)
      if (line !~ /^(#.*)?$/) print line
      line = "" }
    END { gsub(/^[[:space:]]+/, "", line); if (line !~ /^(#.*)?$/) print line }
  '
}

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

echo "== workflow wiring =="
# The helper only protects the workflow while the workflow actually calls it,
# and only while nothing downstream discards the status it propagates. A bare
# `grep` for the call is satisfied by `ct-retry.sh ct lint ... || true`, so
# assert the whole step body instead: one logical command, the helper, no shell
# operator that could swallow its exit status.
for step in lint install; do
  commands="$(step_run_body "$workflow" "Run chart-testing (${step})" | logical_commands)"
  command_count="$(printf '%s\n' "$commands" | grep -c . || true)"

  if [[ "$command_count" -ne 1 ]]; then
    fail "ct ${step} is not the step's only command (${command_count} commands)"
  elif [[ ! "$commands" =~ ^\.github/scripts/ct-retry\.sh[[:space:]]ct[[:space:]]${step}([[:space:]]|$) ]]; then
    fail "ct ${step} does not run through ct-retry.sh (got: ${commands})"
  elif [[ "$commands" == *'|'* || "$commands" == *'&'* || "$commands" == *';'* || "$commands" == *'`'* ]]; then
    fail "ct ${step} is short-circuited (got: ${commands})"
  else
    pass "ct ${step} runs through ct-retry.sh as the step's only command"
  fi
done

# `continue-on-error: true` turns a failing step green without touching the
# command, so no grep of the ct steps themselves would notice it.
if grep -qE '^[[:space:]]*continue-on-error[[:space:]]*:' "$workflow"; then
  fail "a workflow step is marked continue-on-error"
else
  pass "no workflow step is marked continue-on-error"
fi

# This guard is only worth its assertions while the workflow still runs it,
# unconditionally. Deleting the step in the same pull request also deletes the
# run that would report it, so branch protection — not this assertion — is what
# ultimately keeps the step in place; the assertion catches every edit that
# leaves the guard running, such as putting an `if:` on it.
guard_step="Verify CI retry helper"
guard_commands="$(step_run_body "$workflow" "$guard_step" | logical_commands)"
guard_keys="$(step_keys "$workflow" "$guard_step")"

if [[ "$guard_commands" != *"ct-retry-test.sh"* ]]; then
  fail "the workflow no longer runs ${guard_step}"
elif printf '%s\n' "$guard_keys" | grep -qxE 'if'; then
  fail "${guard_step} is conditional"
else
  pass "${guard_step} runs this script unconditionally"
fi

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
