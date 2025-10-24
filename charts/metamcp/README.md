# metamcp Helm Chart

MetaMCP aggregator for Model Context Protocol. It aggregates multiple MCP servers (remote SSE/Streamable HTTP) under a single endpoint (namespace), so clients can connect once and access all tools.

- Keep your MCP servers as independent Deployments and register them as remote servers (URL + optional token) in MetaMCP.
- Define a MetaMCP namespace that selects multiple servers, then expose one endpoint for clients (SSE or Streamable HTTP).

> Note: MetaMCP can also launch STDIO servers as child processes. In Kubernetes, we recommend running each server as its own Pod for observability, security, and scaling, and using MetaMCP only as the aggregator.

## Endpoints

- Frontend (dashboard): `http://<service>:12008`
- Backend (internal): `http://<service>:12009`
- Public MCP endpoints (after defining a namespace):
  - `/metamcp/<namespace>/sse`
  - `/metamcp/<namespace>/mcp`

## Prerequisites

- Kubernetes 1.26+
- Helm 3.10+

## Installing the Chart

```bash
helm upgrade --install metamcp icoretech/metamcp \
  --namespace metamcp --create-namespace
```

## Minimal configuration

```yaml
secretEnv:
  BETTER_AUTH_SECRET: change-me
# Optional explicit external URL if exposed via Ingress/Gateway
# env:
#   APP_URL: http://metamcp.example.com
```

The chart deploys an internal Postgres Deployment/Service and injects `DATABASE_URL` automatically.

## Provisioning

Use `provision.*` to declare servers (STDIO/STREAMABLE_HTTP/SSE), namespaces, and endpoints. For HTTP/SSE, either provide a remote `url` or include deploy specs (`port` + `node`/`python`/`image`) and the chart will run a Pod/Service and auto-register it.

## User seeding (optional)

Seed users at install/upgrade by setting `users` (and optionally disable public signup):

```yaml
disablePublicSignup: true
users:
  - email: admin@example.com
    password: change-me
    name: Admin
    createApiKey: true
    apiKeyName: cli
  - email: analyst@example.com
    password: change-me
    name: Analyst
```

For entries with `createApiKey: true`, the chart creates a Secret named
`<release>-metamcp-apikey-<email-slug>` with fields:

- `data.apiKey`: the generated API key (base64-encoded)
- `data.email`: the user email (base64-encoded)

The first listed user is used to apply `disablePublicSignup` if set.

## Configuration

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

## Notes

- Required env: `APP_URL`, `BETTER_AUTH_SECRET`.
- Required env: `APP_URL`, `BETTER_AUTH_SECRET`.
