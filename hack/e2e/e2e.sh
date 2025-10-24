#!/usr/bin/env bash
set -euo pipefail

CHART=${1:-}
NAMESPACE=${NAMESPACE:-e2e}
TIMEOUT=${TIMEOUT:-50s}
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)

helm_lint() {
  helm lint "$1"
}

install_chart() {
  local chart_dir=$1
  local release=$2
  local values=$3
  kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"
  helm upgrade --install "$release" "$chart_dir" -n "$NAMESPACE" -f "$values" --wait --timeout "$TIMEOUT"
}

case "$CHART" in
  metamcp)
    helm_lint "$ROOT/charts/metamcp"
    install_chart "$ROOT/charts/metamcp" metamcp "$ROOT/charts/metamcp/examples/e2e.yaml"
    ;;
  mcp-server)
    helm dependency update "$ROOT/charts/mcp-server"
    helm_lint "$ROOT/charts/mcp-server"
    install_chart "$ROOT/charts/mcp-server" mcp-server "$ROOT/charts/mcp-server/examples/e2e.yaml"
    ;;
  *)
    echo "Usage: $0 {metamcp|mcp-server} [env NAMESPACE=?, TIMEOUT=?]" >&2
    exit 2
    ;;
 esac

kubectl -n "$NAMESPACE" get pods -o wide
