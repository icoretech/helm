#!/usr/bin/env bash
set -euo pipefail

CHART=${1:-}
NAMESPACE=${NAMESPACE:-e2e}
TIMEOUT=${TIMEOUT:-50s}
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)

cleanup() {
  # kill port-forwards
  pkill -f "port-forward.*12008:12008" >/dev/null 2>&1 || true
  pkill -f "port-forward.*12009:12009" >/dev/null 2>&1 || true
  # delete known namespaces
  kubectl delete ns metamcp metamcp2 metamcp3 e2e --wait=true --ignore-not-found
}

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
    cleanup
    helm_lint "$ROOT/charts/metamcp"
    install_chart "$ROOT/charts/metamcp" metamcp "$ROOT/charts/metamcp/examples/e2e.yaml"
    # port-forward for UI
    (kubectl -n "$NAMESPACE" port-forward svc/metamcp-metamcp 12008:12008 12009:12009 >/tmp/metamcp-e2e-pf.log 2>&1 &) >/dev/null 2>&1
    sleep 1
    echo "MetaMCP UI: http://localhost:12008"
    echo "Admin: admin@example.com / change-me"
    ;;
  mcp-server)
    cleanup
    helm dependency update "$ROOT/charts/mcp-server"
    helm_lint "$ROOT/charts/mcp-server"
    install_chart "$ROOT/charts/mcp-server" mcp-server "$ROOT/charts/mcp-server/examples/e2e.yaml"
    (kubectl -n "$NAMESPACE" port-forward svc/mcp-server-metamcp 12008:12008 12009:12009 >/tmp/mcp-server-e2e-pf.log 2>&1 &) >/dev/null 2>&1
    sleep 1
    echo "MetaMCP (subchart) UI: http://localhost:12008"
    echo "Admin: admin@example.com / change-me"
    ;;
  *)
    echo "Usage: $0 {metamcp|mcp-server} [env NAMESPACE=?, TIMEOUT=?]" >&2
    exit 2
    ;;
 esac

kubectl -n "$NAMESPACE" get pods -o wide
