#!/usr/bin/env bash
set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOYMENT_TEMPLATE="$CHART_DIR/templates/deployment.yaml"
CHART_YAML="$CHART_DIR/Chart.yaml"

APP_VERSION="$(sed -n 's/^appVersion:[[:space:]]*"\{0,1\}\([^" ]*\)"\{0,1\}$/\1/p' "$CHART_YAML" | head -n1)"
if [[ -z "$APP_VERSION" ]]; then
  echo "ERROR: couldn't parse appVersion from $CHART_YAML" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CHART_ENV="$TMP_DIR/chart-env.txt"
SUPPORTED_ENV="$TMP_DIR/supported-env.txt"
UNKNOWN_ENV="$TMP_DIR/unknown-env.txt"

rg -o 'name: [A-Z][A-Z0-9_]+' "$DEPLOYMENT_TEMPLATE" | sed 's/name: //' | sort -u > "$CHART_ENV"

CONFIG_URL="https://raw.githubusercontent.com/browserless/browserless/${APP_VERSION}/src/config.ts"
if ! curl -fsSL "$CONFIG_URL" -o "$TMP_DIR/config.ts"; then
  echo "ERROR: failed to fetch Browserless config source for tag ${APP_VERSION}: $CONFIG_URL" >&2
  exit 1
fi

rg -o 'process\.env\.([A-Z0-9_]+)' "$TMP_DIR/config.ts" -r '$1' | sort -u > "$SUPPORTED_ENV"
rg -o "'([A-Z0-9_]+)'" "$TMP_DIR/config.ts" | tr -d "'" | rg '^[A-Z0-9_]+$' | sort -u >> "$SUPPORTED_ENV"
sort -u "$SUPPORTED_ENV" -o "$SUPPORTED_ENV"

comm -23 "$CHART_ENV" "$SUPPORTED_ENV" > "$UNKNOWN_ENV"

if [[ -s "$UNKNOWN_ENV" ]]; then
  echo "ERROR: chart contains env vars not present in Browserless ${APP_VERSION} config contract:" >&2
  cat "$UNKNOWN_ENV" >&2
  exit 1
fi

echo "Env contract check passed for Browserless ${APP_VERSION}."
