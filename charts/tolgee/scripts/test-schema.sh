#!/usr/bin/env bash
set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$CHART_DIR"

echo "==> Helm version"
helm version --short

echo "==> Lint/template with valid fixtures"
for f in \
  tests/values/valid-minimal.yaml \
  tests/values/valid-external.yaml \
  tests/values/valid-external-secret.yaml \
  tests/values/valid-external-valuefrom.yaml \
  tests/values/valid-metrics-servicemonitor.yaml \
  tests/values/valid-s3-secretrefs.yaml
  do
  echo "  - $f"
  helm lint . -f "$f" >/dev/null
  helm template test . -f "$f" >/dev/null
done

expect_invalid() {
  local values_file="$1"
  echo "  - expecting failure: $values_file"

  if helm lint . -f "$values_file" >/tmp/tolgee-schema-lint.err 2>&1; then
    echo "ERROR: helm lint unexpectedly succeeded for $values_file" >&2
    cat /tmp/tolgee-schema-lint.err >&2 || true
    exit 1
  fi

  if helm template invalid . -f "$values_file" >/tmp/tolgee-schema-template.out 2>/tmp/tolgee-schema-template.err; then
    echo "ERROR: helm template unexpectedly succeeded for $values_file" >&2
    cat /tmp/tolgee-schema-template.out >&2 || true
    exit 1
  fi
}

echo "==> Invalid fixtures must fail"
for f in \
  tests/values/invalid-both-db-modes.yaml \
  tests/values/invalid-external-missing-creds.yaml \
  tests/values/invalid-external-reserved-extraenv.yaml \
  tests/values/invalid-external-wait-missing-host.yaml \
  tests/values/invalid-http-route-parents.yaml \
  tests/values/invalid-jwt-secretref-missing-key.yaml \
  tests/values/invalid-metrics-servicemonitor-without-metrics.yaml \
  tests/values/invalid-nodeport.yaml \
  tests/values/invalid-unknown-top-level.yaml
  do
  expect_invalid "$f"
done

echo "Schema tests passed."
