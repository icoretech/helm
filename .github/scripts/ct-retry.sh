#!/usr/bin/env bash
#
# Retry a command and exit with ITS status.
#
# Replaces an inline retry loop that read `rc=$?` after a false `if`. That reads
# the status of the `if` compound command, which is 0 when the condition failed
# and there is no `else`, so `exit "$rc"` always exited 0: no `ct lint` or
# `ct install` failure could ever fail a pull request.
#
# Env:
#   CT_RETRY_ATTEMPTS         total attempts (default 3, at most 10)
#   CT_RETRY_BACKOFF_SECONDS  base backoff, multiplied by the attempt number
#                             (default 20, at most 600; 0 disables sleeping)
set -uo pipefail

attempts="${CT_RETRY_ATTEMPTS:-3}"
backoff="${CT_RETRY_BACKOFF_SECONDS:-20}"

if [[ "$#" -eq 0 ]]; then
  echo "usage: ct-retry.sh <command> [args...]" >&2
  exit 2
fi

# A non-positive attempt budget skips the loop entirely and used to reach the
# final `exit "$rc"` with rc still 0: the command never ran and the step went
# green. Refuse it instead, so a bad budget fails the step like any other
# configuration error.
max_attempts=10
max_backoff=600

if [[ ! "$attempts" =~ ^[0-9]+$ ]] || [[ "$attempts" -lt 1 ]] || [[ "$attempts" -gt "$max_attempts" ]]; then
  echo "::error::CT_RETRY_ATTEMPTS must be an integer between 1 and ${max_attempts} (got '${attempts}')" >&2
  exit 2
fi

# An enormous budget is not a fail-open — a hung job still fails the check — but
# it burns a runner to the six-hour limit and buries the real failure.
if [[ ! "$backoff" =~ ^[0-9]+$ ]] || [[ "$backoff" -gt "$max_backoff" ]]; then
  echo "::error::CT_RETRY_BACKOFF_SECONDS must be an integer between 0 and ${max_backoff} (got '${backoff}')" >&2
  exit 2
fi

rc=0
for ((attempt = 1; attempt <= attempts; attempt++)); do
  rc=0
  "$@" || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    exit 0
  fi

  if [[ "$attempt" -ge "$attempts" ]]; then
    echo "::error::$1 failed after ${attempt} attempt(s) (exit ${rc})" >&2
    exit "$rc"
  fi

  echo "::warning::$1 failed (exit ${rc}); retrying in $((attempt * backoff))s" >&2
  sleep "$((attempt * backoff))"
done

exit "$rc"
