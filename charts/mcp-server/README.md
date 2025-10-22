# mcp-server Helm Chart

Generic runner for Model Context Protocol (MCP) servers on
Kubernetes.

This chart supports three modes:

- `image`: run a pre-built container image that already includes your MCP
  server (recommended for production).
- `node`: run a Node/TypeScript MCP server package via `npx` inside a
  `node:alpine` container.
- `python`: run a Python MCP server via `uvx` (or `pip`) inside a `uv`/`python`
  container.

## Named Servers

Run many stdio‑based MCP servers behind a single HTTP(SSE) endpoint using the
built‑in gateway option powered by `mcp-proxy`.

What it is

- One process exposes an SSE endpoint and spawns multiple stdio MCP servers as
  child processes.
- Each server is reachable at `/servers/{name}/sse` (a default server can also
  be exposed at `/sse`).

Why it’s useful

- One Service/Ingress/Gateway for multiple stdio MCP servers.
- Central place for long‑lived connection tuning (SSE/WS timeouts).
- Great for internal hubs, demos, or small fleets.

When not to use

- If you need per‑server autoscaling/isolation, prefer multiple Deployments or
  an external reverse proxy.

How to enable

- Set `transport.type: stdio` and `transport.stdioGateway.enabled: true`.
- Add entries under `transport.stdioGateway.servers` with `command`/`args`/`env`.
- Or provide raw JSON via `transport.stdioGateway.namedServersJson`.
- Use `transport.stdioGateway.preStart` for installing servers (e.g., pip
  install) or ship a custom image.

Endpoints

- Default: `/sse` (if you spawn a default server after `--`).
- Named: `/servers/{name}/sse`.
- Status: `/status`.

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
| additionalAnnotations | object | `{}` | Additional annotations applied to chart resources |
| additionalLabels | object | `{}` | Additional labels applied to chart resources |
| affinity | object | `{}` | Affinity rules for Pod scheduling |
| autoscaling | object | `{"enabled":false,"maxReplicas":5,"minReplicas":1,"targetCPUUtilizationPercentage":80}` | Horizontal Pod Autoscaler configuration |
| config.contents | string | `"# example config\n# [server]\n# port = 3000\n"` | Raw contents of the config file |
| config.enabled | bool | `false` |  |
| config.filename | string | `"config.toml"` | Filename within the mount path (e.g., config.toml, config.yaml, config.json) |
| config.mountPath | string | `"/config"` | Mount path inside the container |
| container.args | list | `[]` | Override container args (array form) |
| container.command | list | `[]` | Override container command (array form) |
| container.env | list | `[]` | Extra environment variables |
| container.extraEnvFrom | list | `[]` | Extra envFrom entries (e.g., Secret or ConfigMap refs) |
| container.port | int | `3000` | Port the MCP server listens on (if using HTTP/WebSocket) |
| container.workingDir | string | `""` | Working directory for the server process |
| fullnameOverride | string | `""` | Completely overrides the generated name |
| httpRoute.annotations | object | `{}` |  |
| httpRoute.enabled | bool | `false` |  |
| httpRoute.hostnames[0] | string | `"mcp.example.local"` |  |
| httpRoute.parentRefs[0].name | string | `"gateway"` |  |
| httpRoute.parentRefs[0].sectionName | string | `"http"` |  |
| httpRoute.rules | list | `[]` |  |
| image.args | list | `[]` | Optional override of args when mode=image (array form) |
| image.command | list | `[]` | Optional override of command when mode=image (array form) |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.repository | string | `"nginx"` | Image repository |
| image.tag | string | `""` | Image tag (defaults to Chart.AppVersion when empty) |
| imagePullSecrets | list | `[]` | Image pull secrets for private registries |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `""` |  |
| ingress.enabled | bool | `false` |  |
| ingress.hosts[0].host | string | `"mcp.example.local"` |  |
| ingress.hosts[0].paths[0].path | string | `"/"` |  |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| ingress.tls | list | `[]` |  |
| livenessProbe | object | `{}` | Liveness probe (disabled by default; many MCP servers don’t expose HTTP health) |
| mode | string | `"image"` | Runtime mode for the MCP server. One of: `image`, `node`, `python`.    - `image`: run a pre-built container image (recommended for production)    - `node`: run a Node/TypeScript MCP package via `npx`    - `python`: run a Python MCP package via `uvx` (or pip) |
| nameOverride | string | `""` | Overrides the chart name for resources |
| node.args | list | `[]` | Arguments to pass to the package, e.g. ["--port", "3000"] |
| node.image | string | `"node:24-alpine"` | Node base image to run npx |
| node.npmrcMountPath | string | `"/home/node/.npmrc"` | Mount path for the .npmrc file |
| node.npmrcSecret | string | `""` | Optional private registry auth: mount a Secret containing an ".npmrc" key |
| node.package | string | `""` | npm package name, e.g. "mcp-remote" or "@acme/my-mcp-server" |
| node.preStart | list | `[]` | Optional additional setup commands before starting the server |
| node.pullPolicy | string | `"IfNotPresent"` | Pull policy for the Node image |
| node.version | string | `"latest"` | Optional semver or dist-tag to pin, e.g. "latest" or "1.2.3" |
| nodeSelector | object | `{}` | Node selector for Pod assignment |
| podAnnotations | object | `{}` | Annotations added to the Pod |
| podLabels | object | `{}` | Labels added to the Pod |
| podSecurityContext | object | `{}` | Pod-level security context |
| python.args | list | `[]` | Extra args for the package (e.g., ["--port", "3000"]) |
| python.fromGit | string | `""` | Optional Git source for uvx (e.g. git+https://...). If set, `package` is executed from this source |
| python.image | string | `"ghcr.io/astral-sh/uv:latest"` | Base image with uv/uvx and Python preinstalled. Alternative: python:3.12-slim |
| python.package | string | `""` | uvx target, e.g. "awslabs.aws-pricing-mcp-server@latest" or a local module name |
| python.preStart | list | `[]` | Optional pre-start commands (e.g., install requirements) |
| python.pullPolicy | string | `"IfNotPresent"` | Pull policy for the Python image |
| python.usePip | bool | `false` | Use pip instead of uvx (set to true to use pip) |
| readinessProbe | object | `{}` | Readiness probe (disabled by default) |
| replicaCount | int | `1` | Number of replicas for the Deployment |
| resources | object | `{}` | Resource requests/limits for the container |
| securityContext | object | `{}` | Container-level security context |
| service.port | int | `3000` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.automount | bool | `true` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| tolerations | list | `[]` | Tolerations to allow Pods to be scheduled onto nodes with taints |
| transport | object | `{"http":{"path":"/sse","timeouts":{"proxySeconds":3600,"readSeconds":3600,"sendSeconds":3600},"wsPath":"/ws"},"stdioGateway":{"allowOrigins":["*"],"cwd":"","enabled":false,"env":[],"envFrom":[],"host":"0.0.0.0","image":"ghcr.io/sparfenyuk/mcp-proxy:latest","namedServersJson":"","passEnvironment":true,"port":8096,"preStart":[],"pullPolicy":"IfNotPresent","resources":{},"server":{"args":[],"command":"","cwd":"","env":[]},"servers":{}},"type":"http-sse"}` | Transport configuration |
| transport.http.path | string | `"/sse"` | Base HTTP path for the MCP endpoint (e.g., `/sse` for streamable HTTP using SSE).    This is used only for documentation/ingress convenience; your server must actually    listen on this path. |
| transport.http.timeouts | object | `{"proxySeconds":3600,"readSeconds":3600,"sendSeconds":3600}` | Recommended long-lived connection timeouts (applied as Ingress annotations where supported). |
| transport.http.wsPath | string | `"/ws"` | Optional alternate WebSocket path if using `transport.type=websocket` |
| transport.stdioGateway | object | `{"allowOrigins":["*"],"cwd":"","enabled":false,"env":[],"envFrom":[],"host":"0.0.0.0","image":"ghcr.io/sparfenyuk/mcp-proxy:latest","namedServersJson":"","passEnvironment":true,"port":8096,"preStart":[],"pullPolicy":"IfNotPresent","resources":{},"server":{"args":[],"command":"","cwd":"","env":[]},"servers":{}}` | Optional stdio gateway to translate stdio↔network inside the pod. Disabled by default. |
| transport.stdioGateway.allowOrigins | list | `["*"]` | Add one or more CORS origins (use ["*"] for any) |
| transport.stdioGateway.cwd | string | `""` | Working directory for the spawned stdio server process |
| transport.stdioGateway.env | list | `[]` | Additional env just for the gateway container |
| transport.stdioGateway.envFrom | list | `[]` | envFrom for the gateway container (e.g., secrets/configmaps) |
| transport.stdioGateway.image | string | `"ghcr.io/sparfenyuk/mcp-proxy:latest"` | Gateway container image (defaults to a public mcp-proxy that can expose SSE and spawn a local stdio server) |
| transport.stdioGateway.namedServersJson | string | `""` | Advanced: provide a raw JSON string for named servers config (overrides servers map) |
| transport.stdioGateway.passEnvironment | bool | `true` | Pass all environment variables through to the spawned stdio server |
| transport.stdioGateway.port | int | `8096` | Port for the gateway's SSE server to listen on (use service.port externally) |
| transport.stdioGateway.preStart | list | `[]` | Optional commands to run before starting the proxy (e.g., pip installs) |
| transport.stdioGateway.resources | object | `{}` | Resources for the gateway container |
| transport.stdioGateway.server | object | `{"args":[],"command":"","cwd":"","env":[]}` | Optional explicit stdio server to spawn (overrides mode-based auto command) |
| transport.stdioGateway.servers | object | `{}` | Define multiple named stdio servers served under `/servers/{name}/` paths.    Each entry supports: command, args[], env[] (list of {name,value}), disabled (bool) |
| transport.type | string | `"http-sse"` | Primary transport type exposed outside the pod. One of: `http-sse`, `websocket`, `stdio`.    Note: `stdio` is generally unsuitable for remote access in Kubernetes unless you wrap the    server with a gateway that translates stdio to a network transport. |
| volumeMounts | list | `[]` | Additional volume mounts for the container |
| volumes | list | `[]` | Additional volumes to add to the Pod |
<!-- markdownlint-enable MD013 -->

## Transports and Exposure

Transports

- `http-sse` (default): stream over a long‑lived HTTP connection.
- `websocket`: stream over WebSocket.
- `stdio`: intended for local clients; in Kubernetes it needs a gateway/bridge.
  This chart offers a stdio gateway mode using `mcp-proxy`.

Exposure options

- ClusterIP + port‑forward: simplest local testing.
- Ingress (e.g., NGINX): add WS upgrade annotations and increase timeouts.
- Gateway API (HTTPRoute): set `rules.timeouts.request/backendRequest` for
  long‑lived connections.

Timeout tips

- SSE: raise read/send/proxy timeouts (NGINX `proxy-read-timeout` and
  `proxy-send-timeout` to `3600`).
- WebSocket: ensure upgrade support (NGINX: `enable-websocket: "true"`).

## Examples

Node mode (npx):

```yaml
mode: node
node:
  image: node:24-alpine
  package: mcp-remote
  version: latest
  args:
    - https://docs.mcp.cloudflare.com/sse
    - --port
    - "3000"
container:
  port: 3000
service:
  port: 3000
```

Python mode (uvx):

```yaml
mode: python
python:
  image: ghcr.io/astral-sh/uv:latest
  package: awslabs.aws-documentation-mcp-server@latest
  args:
    - --port
    - "3000"
container:
  port: 3000
service:
  port: 3000
```

Stdio gateway with named servers (mcp-proxy):

```yaml
# Exposes /sse for default server and /servers/{name}/sse for named servers
mode: python
python:
  image: ghcr.io/astral-sh/uv:latest
  package: awslabs.aws-documentation-mcp-server@latest
  args:
    - --port
    - "3000"
service:
  port: 3000
transport:
  type: stdio
  stdioGateway:
    enabled: true
    image: ghcr.io/sparfenyuk/mcp-proxy:latest
    passEnvironment: true
    allowOrigins: ["*"]
    preStart:
      - pip install --no-cache-dir awslabs.aws-documentation-mcp-server awslabs.aws-pricing-mcp-server
    servers:
      docs:
        command: awslabs.aws-documentation-mcp-server
      pricing:
        command: awslabs.aws-pricing-mcp-server
```

WebSocket via NGINX Ingress:

```yaml
service:
  port: 3000
container:
  port: 3000
transport:
  type: websocket
  http:
    wsPath: /ws
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/enable-websocket: "true"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  hosts:
    - host: mcp.example.local
      paths:
        - path: /
          pathType: Prefix
```

Example values files are provided under `charts/mcp-server/examples/`:

- `node-mcp-remote.yaml`: Node mode using `mcp-remote`.
- `python-aws-docs.yaml`: Python mode using `awslabs.aws-documentation-mcp-server`.
- `stdio-gateway-named-servers.yaml`: Stdio gateway with two named servers.
- `ingress-websocket-nginx.yaml`: WebSocket transport behind NGINX Ingress.
- `gateway-http.yaml`: Minimal Gateway (Gateway API) to attach HTTPRoutes.
- `httproute-sse-gatewayapi.yaml`: HTTPRoute with timeouts for SSE/Streamable HTTP.
- `httproute-websocket-gatewayapi.yaml`: HTTPRoute with timeouts for WebSocket.

Gateway API quickstart:

```bash
# Install a Gateway in the same namespace as your release (default: mcp)
kubectl apply -f charts/mcp-server/examples/gateway-http.yaml

# Deploy the chart with an HTTPRoute example (SSE)
helm upgrade --install mcp-sse charts/mcp-server -n mcp -f charts/mcp-server/examples/httproute-sse-gatewayapi.yaml

# The route attaches to Gateway "gateway" listener "http"
```
