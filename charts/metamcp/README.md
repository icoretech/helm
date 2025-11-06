# MetaMCP Helm Chart

Deploys MetaMCP and a declarative provisioning system that:

- Aggregates many MCP servers behind a single endpoint (namespace) for clients.
- Optionally deploys your HTTP/SSE MCP servers as Pods and auto‑registers them as remote servers in MetaMCP.
- Can also register remote URLs you host elsewhere (no Pod created here).
- Can run STDIO servers inside MetaMCP itself when configured (ensure required runtimes exist in the MetaMCP image).

In short: this chart both installs MetaMCP and can pre‑configure it (servers → namespaces → endpoints) from values.yaml. No manual clicking or ad‑hoc scripts required.

## Endpoints

- Frontend (dashboard): `http://<service>:12008`
- Backend (internal): `http://<service>:12009`
- MCP endpoint examples after provisioning namespace `lab`:
  - SSE: `http://<service>:12008/metamcp/lab/sse`
  - Streamable HTTP: `http://<service>:12008/metamcp/lab/mcp`

## Install

```bash
helm upgrade --install metamcp icoretech/metamcp \
  -n metamcp --create-namespace \
  --set auth.betterAuthSecret=change-me \
  --set env.APP_URL=http://metamcp-metamcp.metamcp.svc.cluster.local:12008
```

Notes
- Internal Postgres is bundled and `DATABASE_URL` is auto‑injected. To point to an external DB, just override `env.DATABASE_URL`; there is no dedicated `externalPostgres` block.
- Required: set `auth.betterAuthSecret`. Set `env.APP_URL` to the in‑cluster Service URL (or your public hostname) so cookies work correctly.
- Pod rollouts on change: the chart annotates the MetaMCP Deployment with checksums of the base ConfigMap/Secret and every `extraEnvFrom` Secret/ConfigMap it references (looked up at render time). When those objects change and Helm/Flux reconciles, Pods restart to pick up new values.

## Provisioning model

Declare everything under `provision.*`:

- Servers:
  - `type: STDIO` → MetaMCP spawns the process inside its container using `command` + `args` (+ optional `env`). Ensure the MetaMCP image contains the required runtime (e.g., Node/PNPM/NPM or Python/uv).
  - `type: STREAMABLE_HTTP` or `SSE`:
    - remote: provide `url` (no Pod is created here) + optional `bearerToken`/`headers`.
    - deploy: provide one of `node`/`python`/`image` and optionally `port` (defaults to `3001`);
      the chart creates a Deployment/Service and auto‑derives the URL for registration.
- Namespaces: group servers by name.
- Endpoints: expose a namespace via `transport: SSE | STREAMABLE_HTTP`. Note: `STDIO` is a server run mode, not an endpoint transport.

Example

```yaml
auth:
  betterAuthSecret: dev-secret
env:
  APP_URL: http://metamcp-metamcp.<namespace>.svc.cluster.local:12008

users:
  - email: admin@example.com
    password: change-me
    name: Admin

provision:
  enabled: true
  servers:
    # STDIO executed by MetaMCP
    - name: stdio-everything
      type: STDIO
      command: "npx"
      args: ["-y","@modelcontextprotocol/server-everything","stdio"]

    # Streamable HTTP & SSE servers deployed by this chart and auto-registered
    - name: http-everything
      type: STREAMABLE_HTTP
      port: 3001
      node:
        package: "@modelcontextprotocol/server-everything"
        version: "latest"
        args: ["streamableHttp","--port","3001"]
    - name: sse-everything
      type: SSE
      port: 3001
      node:
        package: "@modelcontextprotocol/server-everything"
        version: "latest"
        args: ["sse","--port","3001"]

  namespaces:
    - name: lab
      description: "Sandbox tools"
      servers: ["stdio-everything","http-everything","sse-everything"]

  endpoints:
    - name: lab
      namespace: lab
      description: "Public lab endpoint"
      transport: SSE
      # Optional auth controls (match UI):
      enableApiKeyAuth: true
      useQueryParamAuth: false
      enableOauth: false
```

## User seeding (optional)

The chart can create users at install/upgrade and optionally generate API keys (stored in Secrets named like `<release>-metamcp-apikey-<email-slug>`):

```yaml
disablePublicSignup: true
users:
  - email: admin@example.com
    password: change-me
    name: Admin
    createApiKey: true
    apiKeyName: cli
```

Provisioning authentication

- The provisioning Job authenticates using the first entry in `users` (email/password).
- If `users` is empty, it falls back to `admin@example.com` / `change-me` for quick‑start only.
- In production, always set `users[0]` and consider `disablePublicSignup: true`.

## Configuration reference

<!-- markdownlint-disable MD013 -->
## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| auth.betterAuthSecret | string | `""` |  |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `5` |  |
| autoscaling.minReplicas | int | `1` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| autoscaling.targetMemoryUtilizationPercentage | string | `nil` |  |
| disablePublicSignup | bool | `false` |  |
| env | object | `{}` |  |
| extraEnv | list | `[]` |  |
| extraEnvFrom | list | `[]` |  |
| fullnameOverride | string | `""` |  |
| gatewayAPI.enabled | bool | `false` |  |
| gatewayAPI.hosts | list | `[]` |  |
| gatewayAPI.mapBackendPaths | bool | `true` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"ghcr.io/metatool-ai/metamcp"` |  |
| image.tag | string | `"latest"` |  |
| imagePullSecrets | list | `[]` |  |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `""` |  |
| ingress.enabled | bool | `false` |  |
| ingress.hosts[0].host | string | `"metamcp.local"` |  |
| ingress.hosts[0].paths[0].path | string | `"/"` |  |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| ingress.mapBackendPaths | bool | `true` |  |
| ingress.tls | list | `[]` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| postgres.auth.database | string | `"metamcp"` |  |
| postgres.auth.password | string | `"metamcp"` |  |
| postgres.auth.username | string | `"metamcp"` |  |
| postgres.enabled | bool | `true` |  |
| postgres.image | string | `"postgres:16"` |  |
| postgres.persistence.enabled | bool | `false` |  |
| postgres.persistence.size | string | `"1Gi"` |  |
| postgres.persistence.storageClassName | string | `""` |  |
| provision.enabled | bool | `false` |  |
| provision.endpoints | list | `[]` |  |
| provision.namespaces | list | `[]` |  |
| provision.servers | list | `[]` |  |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
| securityContext | object | `{}` |  |
| service.port | int | `12008` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.automount | bool | `true` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| tolerations | list | `[]` |  |
| users | list | `[]` |  |
<!-- markdownlint-enable MD013 -->

## Design highlights

- Single source of truth: `provision.servers` drives both deployment (optional) and registration.
- Internal Postgres only; external DBs supported by overriding `env.DATABASE_URL`.
- Endpoint transports validated to `SSE` or `STREAMABLE_HTTP`.
- Secrets/configmaps are checksum‑annotated to trigger rollouts when they change.
## Examples

- Minimal e2e (in-cluster URLs, no Ingress): `examples/e2e.yaml`
- Cache PVC per server (requires default StorageClass): `examples/provision-pvc.yaml`
- Advanced options (resources, HPA, probes, volumes, init containers): `examples/provision-advanced.yaml`
# STDIO server with env and Secret-backed env

provision:
  enabled: true
  servers:
    - name: figma
      type: STDIO
      command: "npx"
      args: ["-y", "figma-developer-mcp", "--stdio"]
      # Plain env (non-secret)
      env:
        LOG_LEVEL: debug
      # Secret-backed env for STDIO: use envFrom
      # The provision Job reads Secret/figma-mcp-env and injects all key/values
      # into the MetaMCP server config (not into a Pod), so the STDIO process
      # sees them when MetaMCP launches it.
      envFrom:
        - secretRef:
            name: figma-mcp-env
