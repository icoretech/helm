# mcp-server Helm Chart

Generic runner for Model Context Protocol (MCP) servers on
Kubernetes.

This chart supports four modes:

- `image`: run a pre-built container image that already includes your MCP
  server (recommended for production).
- `node`: run a Node/TypeScript MCP server package via `npx` inside a
  `node:alpine` container.
- `python`: run a Python MCP server via `pipx` inside an official Python
  container.
- `openapi`: do not run a Pod; instead, register an external OpenAPI URL with
  Unla's gateway so it can provision a server from the spec.

## Stdio transport support

This chart supports both HTTP-compatible MCP servers and stdio-only MCP servers. For HTTP-compatible 
servers, Kubernetes pods can run them directly as long‑lived network services. For stdio-only servers, 
the chart provides a `stdioBridge` feature that uses `mcp-proxy` to convert stdio to HTTP transport.

**For HTTP-compatible servers**: Pick servers that expose HTTP (SSE) or WebSocket natively.
**For stdio-only servers**: Use the `stdioBridge` feature to wrap them with an HTTP proxy layer.

**Important**: Many popular MCP servers (available via npx/uvx) like 
`awslabs.aws-documentation-mcp-server` and `awslabs.aws-pricing-mcp-server` are stdio-only and will 
exit when run without the stdioBridge. These servers will initialize and then exit cleanly (exit code 0) 
when run directly, causing Kubernetes to restart them in a CrashLoopBackOff state. 

Use either:
1. **HTTP-compatible servers** (built with streamable-http or SSE support), or
2. **Stdio-only servers with the stdioBridge feature** (uses mcp-proxy to keep the process alive and convert transport)

For details on the stdioBridge feature and examples, please refer to the examples directory.

## Prerequisites

- Kubernetes 1.31+
- Helm 3.10+

## Installing the Chart

To install with the release name `my-mcp` from OCI:

```bash
helm install my-mcp oci://ghcr.io/icoretech/charts/mcp-server
```

Or from the GitHub Pages helm repo:

```bash
helm repo add icoretech https://icoretech.github.io/helm
helm repo update
helm install my-mcp icoretech/mcp-server
```

## Configuration

The following table lists the configurable parameters of the chart and their
default values.

<!-- markdownlint-disable MD013 -->
## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| additionalAnnotations | object | `{}` |  |
| additionalLabels | object | `{}` |  |
| affinity | object | `{}` | Affinity rules for Pod scheduling |
| autoscaling | object | `{"enabled":false,"maxReplicas":5,"minReplicas":1,"targetCPUUtilizationPercentage":80}` | Horizontal Pod Autoscaler configuration |
| config.contents | string | `"# example config\n# [server]\n# port = 3000\n"` | Raw contents of the config file |
| config.enabled | bool | `false` |  |
| config.filename | string | `"config.toml"` | Filename within the mount path (e.g., config.toml, config.yaml, config.json) |
| config.mountPath | string | `"/config"` | Mount path inside the container |
| fullnameOverride | string | `""` | Completely overrides the generated name |
| imagePullSecrets | list | `[]` | Image pull secrets for private registries |
| nameOverride | string | `""` | Overrides the chart name for resources |
| nodeSelector | object | `{}` | Node selector for Pod assignment |
| podAnnotations | object | `{}` | Annotations added to the Pod |
| podLabels | object | `{}` | Labels added to the Pod |
| podSecurityContext | object | `{}` | Pod-level security context |
| replicaCount | int | `1` | Number of replicas for the Deployment |
| resources | object | `{}` | Resource requests/limits for the container |
| securityContext | object | `{}` | Container-level security context |
| servers | list | `[]` | List of MCP servers to run side-by-side in one Pod |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.automount | bool | `true` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| tolerations | list | `[]` | Tolerations to allow Pods to be scheduled onto nodes with taints |
| volumeMounts | list | `[]` | Additional volume mounts for the container |
| volumes | list | `[]` | Additional volumes to add to the Pod |
<!-- markdownlint-enable MD013 -->

## Transports and Exposure

Transports

- HTTP (SSE/streamable HTTP): long‑lived HTTP connection.
- WebSocket: use when your server exposes a WS endpoint.

Exposure options

- ClusterIP + port-forward: simplest local testing.
- Ingress (e.g., NGINX): add WS upgrade annotations and increase timeouts.
- Gateway API (HTTPRoute): set `rules.timeouts.request/backendRequest` for
  long-lived connections.

Timeout tips

- SSE: raise read/send/proxy timeouts (NGINX `proxy-read-timeout` and
  `proxy-send-timeout` to `3600`).
- WebSocket: ensure upgrade support (NGINX: `enable-websocket: "true"`).

## Dependency Caching

Cold starts that download packages can easily exceed tight readiness budgets.
Each runtime offers a cache volume:

- `python.cache.*`: Enabled by default. Persists `pip`/`pipx` artifacts between
  pod restarts. Provide `existingClaim` to re-use a PVC or leave empty to let
  the chart create a 1Gi claim per release.
- `node.cache.*`: Enabled by default. Persists the NPM cache for `npx`
  executions—handy for large packages or private registries.
If no `existingClaim` is supplied, the chart creates PVCs named with the
release suffixes `-py-cache` and `-npm-cache`.

## Examples provided under `charts/mcp-server/examples/`

- `node-server-everything.yaml` - Node mode using
  `@modelcontextprotocol/server-everything` (streamable HTTP pinned to Node 22).
- `python-git-mcp.yaml` - Minimal Python mode example running the
  Git MCP server (HTTP/SSE) - NOTE: may not work due to stdio-only limitation.
- `python-reddit-mcp.yaml` - Python mode example running the
  Reddit MCP server (HTTP/SSE) - NOTE: may not work due to stdio-only limitation.
- `python-fastmcp-http.yaml` - Advanced Python mode running the
  `mcp-server` sample with streamable HTTP arguments - NOTE: may not work due to stdio-only limitation.
- `python-aws-docs-bridge.yaml` - Python stdio-only server using stdioBridge 
  feature to wrap awslabs.aws-documentation-mcp-server with HTTP proxy.
- `python-aws-pricing-bridge.yaml` - Python stdio-only server using stdioBridge 
  feature to wrap awslabs.aws-pricing-mcp-server with HTTP proxy.
- `ingress-websocket-nginx.yaml` - WebSocket transport behind NGINX Ingress.
- `gateway-http.yaml` - Minimal Gateway (Gateway API) to attach HTTPRoutes.
- `gateway-two-servers.yaml` - Gateway-centric deployment with two Node
  servers (using same server-everything package twice due to stdio-only limitation of other servers).
- `helmrelease-git-mcp.yaml` - Flux HelmRelease for Git MCP server 
  (replaced aws-docs with git server due to stdio-only limitation).
- `httproute-sse-gatewayapi.yaml` - Gateway API HTTPRoute tuned for SSE /
  streamable HTTP timeouts.
- `httproute-websocket-gatewayapi.yaml` - Gateway API HTTPRoute prepared for
  WebSocket upgrades.
 

Gateway API quickstart:

```bash
# Install a Gateway in the same namespace as your release (default: mcp)
kubectl apply -f charts/mcp-server/examples/gateway-http.yaml

# Deploy the chart with an HTTPRoute example (SSE)
helm upgrade --install mcp-sse charts/mcp-server -n mcp -f charts/mcp-server/examples/httproute-sse-gatewayapi.yaml

# The route attaches to Gateway "gateway" listener "http"
```
