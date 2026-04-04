#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHART="$ROOT"

run_expect_success() {
  local values_file=$1
  helm lint "$CHART" -f "$values_file" >/tmp/metamcp-schema-success.log
}

run_expect_failure() {
  local values_file=$1
  if helm lint "$CHART" -f "$values_file" >/tmp/metamcp-schema-failure.log 2>&1; then
    echo "expected helm lint to fail for $values_file" >&2
    cat /tmp/metamcp-schema-failure.log >&2
    exit 1
  fi
}

run_expect_success "$ROOT/ci/prune-valid-values.yaml"
run_expect_failure "$ROOT/ci/prune-invalid-run-on-upgrade.yaml"
run_expect_failure "$ROOT/ci/prune-invalid-update-existing.yaml"
