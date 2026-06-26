#!/usr/bin/env bash
set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$CHART_DIR"

echo "==> Helm version"
helm version --short

echo "==> Lint/template with valid fixtures"
for f in \
  tests/values/valid-minimal.yaml \
  tests/values/valid-secrets-create.yaml \
  tests/values/valid-monitoring-bearer-token.yaml
  do
  echo "  - $f"
  helm lint . -f "$f" >/dev/null
  helm template test . -f "$f" >/dev/null
done

expect_invalid() {
  local values_file="$1"
  echo "  - expecting failure: $values_file"

  if helm lint . -f "$values_file" >/tmp/codex-pooler-schema-lint.err 2>&1; then
    echo "ERROR: helm lint unexpectedly succeeded for $values_file" >&2
    cat /tmp/codex-pooler-schema-lint.err >&2 || true
    exit 1
  fi

  if helm template invalid . -f "$values_file" >/tmp/codex-pooler-schema-template.out 2>/tmp/codex-pooler-schema-template.err; then
    echo "ERROR: helm template unexpectedly succeeded for $values_file" >&2
    cat /tmp/codex-pooler-schema-template.out >&2 || true
    exit 1
  fi
}

echo "==> Invalid fixtures must fail"
for f in \
  tests/values/invalid-image-pull-policy.yaml \
  tests/values/invalid-ingress-path-type.yaml \
  tests/values/invalid-lifecycle-schema.yaml \
  tests/values/invalid-monitoring-bearer-secret.yaml \
  tests/values/invalid-secrets-create-missing-values.yaml \
  tests/values/invalid-unknown-top-level.yaml
  do
  expect_invalid "$f"
done

echo "==> preStop values remain shell-safe when schema validation is bypassed"
adversarial_render="$(mktemp)"
helm template adversarial . \
  --skip-schema-validation \
  --show-only templates/app-deployment.yaml \
  --set-string 'app.lifecycle.preStop.drainTimeoutSeconds=1; touch /tmp/owned #' \
  --set-string 'app.lifecycle.preStop.sleepSeconds=2; touch /tmp/sleep-owned #' \
  >"$adversarial_render"

if grep -E ';[[:space:]]*touch|touch /tmp/owned|touch /tmp/sleep-owned' "$adversarial_render" >/dev/null; then
  echo "ERROR: adversarial preStop values rendered shell injection payload" >&2
  cat "$adversarial_render" >&2
  rm -f "$adversarial_render"
  exit 1
fi
rm -f "$adversarial_render"

echo "Schema tests passed."
