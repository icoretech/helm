#!/usr/bin/env bash
set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
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
  tests/values/valid-s3-secretrefs.yaml \
  tests/values/valid-azure-inline.yaml \
  tests/values/valid-azure-secretref.yaml \
  tests/values/valid-released-config.yaml \
  tests/values/valid-runtime-configuration.yaml \
  tests/values/valid-global.yaml
  do
  echo "  - $f"
  helm lint . -f "$f" >/dev/null
  helm template test . -f "$f" >/dev/null
done

expect_invalid() {
  local values_file="$1"
  echo "  - expecting failure: $values_file"

  if helm lint . -f "$values_file" >"$TMP_DIR/lint.err" 2>&1; then
    echo "ERROR: helm lint unexpectedly succeeded for $values_file" >&2
    cat "$TMP_DIR/lint.err" >&2 || true
    exit 1
  fi

  if helm template invalid . -f "$values_file" >"$TMP_DIR/template.out" 2>"$TMP_DIR/template.err"; then
    echo "ERROR: helm template unexpectedly succeeded for $values_file" >&2
    cat "$TMP_DIR/template.out" >&2 || true
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
  tests/values/invalid-unknown-top-level.yaml \
  tests/values/invalid-global-type.yaml \
  tests/values/invalid-azure-s3.yaml \
  tests/values/invalid-azure-container.yaml \
  tests/values/invalid-azure-connection.yaml \
  tests/values/invalid-azure-partial-ref.yaml \
  tests/values/invalid-azure-ref-key-only.yaml \
  tests/values/invalid-oauth-redirect.yaml \
  tests/values/invalid-oauth-browser-extension-enabled.yaml \
  tests/values/invalid-oauth-cli-enabled.yaml \
  tests/values/invalid-oauth-cimd-enabled.yaml \
  tests/values/invalid-oauth-cimd-host.yaml \
  tests/values/invalid-oauth-lifetime.yaml \
  tests/values/invalid-oauth-retention.yaml \
  tests/values/invalid-async-keepalive.yaml \
  tests/values/invalid-async-type.yaml \
  tests/values/invalid-rate-limits.yaml \
  tests/values/invalid-startup-success-threshold.yaml \
  tests/values/invalid-startup-period.yaml \
  tests/values/invalid-deployment-annotation.yaml \
  tests/values/invalid-extra-volume.yaml \
  tests/values/invalid-extra-volume-mount.yaml \
  tests/values/invalid-reserved-volume.yaml
  do
  expect_invalid "$f"
done

echo "==> Packaged chart as a wrapper dependency"
mkdir -p "$TMP_DIR/wrapper/charts"
cp tests/fixtures/wrapper/Chart.yaml.fixture "$TMP_DIR/wrapper/Chart.yaml"
helm package . --destination "$TMP_DIR/wrapper/charts" >/dev/null
for parent_values in "" tests/values/valid-global.yaml; do
  if [[ -n "$parent_values" ]]; then
    helm lint "$TMP_DIR/wrapper" -f "$parent_values" >/dev/null
    helm template wrapper "$TMP_DIR/wrapper" -f "$parent_values" >/dev/null
  else
    helm lint "$TMP_DIR/wrapper" >/dev/null
    helm template wrapper "$TMP_DIR/wrapper" >/dev/null
  fi
done
helm template wrapper "$TMP_DIR/wrapper" -f tests/values/valid-global.yaml \
  -f tests/fixtures/wrapper/external-values.yaml >/dev/null
if helm template wrapper "$TMP_DIR/wrapper" -f tests/values/valid-global.yaml \
  --set tolgee.unknownSetting=true >"$TMP_DIR/wrapper.out" 2>"$TMP_DIR/wrapper.err"; then
  echo "ERROR: wrapper dependency accepted an unknown Tolgee value" >&2
  exit 1
fi
if ! grep -q 'unknownSetting' "$TMP_DIR/wrapper.err"; then
  cat "$TMP_DIR/wrapper.err" >&2
  exit 1
fi

echo "Schema tests passed."
