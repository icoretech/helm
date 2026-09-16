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
#   CT_RETRY_ATTEMPTS         total attempts (default 3)
#   CT_RETRY_BACKOFF_SECONDS  base backoff, multiplied by the attempt number
#                             (default 20; 0 disables sleeping)
set -uo pipefail

attempts="${CT_RETRY_ATTEMPTS:-3}"
backoff="${CT_RETRY_BACKOFF_SECONDS:-20}"

if [[ "$#" -eq 0 ]]; then
  echo "usage: ct-retry.sh <command> [args...]" >&2
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
