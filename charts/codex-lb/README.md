# Codex LB Helm Chart

Deploy [Codex LB](https://github.com/Soju06/codex-lb) on Kubernetes — a load balancer and account pool for proxying ChatGPT / OpenAI API requests across multiple accounts.

## Features

- SQLite by default (zero-dependency), PostgreSQL optional via `config.databaseUrl`
- Persistent volume for the SQLite database and Fernet encryption key
- Encryption key management: auto-generated on PVC or injected via existing Secret
- Explicit operating modes: standalone `Deployment` and replicated `StatefulSet`
- Replicated mode adds an internal handoff Service plus automatic response-owner advertise URL wiring
- Continuity-aware routing for response-owner APIs through both Ingress and Gateway API
- OAuth callback flow for adding ChatGPT accounts (separate Service + Ingress)
- Ingress and Gateway API `HTTPRoute` support (main API and OAuth callback)
- Configurable upstream, firewall, streaming, and model registry settings

## Prerequisites

- Kubernetes 1.24+
- Helm 3.10+

## Install

```bash
helm repo add icoretech https://icoretech.github.io/helm
helm repo update
helm upgrade --install codex-lb icoretech/codex-lb \
  -n codex-lb --create-namespace
```

OCI:

```bash
helm upgrade --install codex-lb oci://ghcr.io/icoretech/charts/codex-lb \
  -n codex-lb --create-namespace
```

## Operating Modes

### Standalone mode (default)

Standalone mode keeps the current iCoreTech chart identity:

- `topology.mode: standalone`
- single replica only
- SQLite by default
- optional PVC for local data and encryption key persistence
- `Deployment` with `Recreate` strategy to avoid RWO multi-attach issues

This is the right mode for low-friction installs, local clusters, and simple single-instance deployments.

### Replicated mode

Replicated mode backports the upstream health-critical pieces for multi-pod operation without copying the whole official chart contract:

- `topology.mode: replicated`
- `StatefulSet` workload
- internal headless handoff Service for stable pod DNS
- automatic `CODEX_LB_HTTP_RESPONSES_SESSION_BRIDGE_INSTANCE_ID=$(POD_NAME)` wiring
- automatic owner-handoff advertise URL derived from pod DNS unless you override it
- continuity routes for `/v1/responses` and `/backend-api/codex/responses`

Replicated mode is intentionally stricter:

- external PostgreSQL only
- `replicaCount >= 2`
- `persistence.enabled: false`
- `config.databaseMigrateOnStartup: false`
- `migration.enabled: true`
- `migration.schemaGate.enabled: true`
- `encryptionKey.existingSecret` is required so all pods share the same Fernet key

Example:

```yaml
topology:
  mode: replicated

replicaCount: 2

config:
  databaseMigrateOnStartup: false

migration:
  enabled: true
  schemaGate:
    enabled: true

persistence:
  enabled: false

envFrom:
  - secretRef:
      name: codex-lb-env

encryptionKey:
  existingSecret:
    name: codex-lb-encryption
    key: fernet-key
```

By default replicated mode derives the owner-handoff base URL from stable pod DNS:

```text
http://$(POD_NAME).<release>-codex-lb-handoff.$(POD_NAMESPACE).svc.<clusterDomain>:2455
```

The default `clusterDomain` is `cluster.local`. Only override `replication.handoffAdvertiseUrl` when pods must be reached through a different internal address.

## Encryption Key via Secret (recommended for production)

The encryption key protects all stored OAuth tokens. Losing it requires re-authenticating every ChatGPT account.

```yaml
encryptionKey:
  existingSecret:
    name: codex-lb-encryption
    key: fernet-key
```

## External PostgreSQL

```yaml
config:
  databaseUrl: "postgresql+asyncpg://user:pass@postgres.example.com:5432/codexlb"

persistence:
  enabled: false   # no SQLite file needed
```

For secret-backed deployments, avoid putting the URL in `config.databaseUrl`, because that renders it into the Deployment manifest. Instead inject `CODEX_LB_DATABASE_URL` from a Secret:

```yaml
envFrom:
  - secretRef:
      name: codex-lb-env

persistence:
  enabled: false
```

That secret-backed URL injection is the recommended base for replicated mode as well.

## Database Migrations

By default Codex LB runs Alembic migrations on startup (`config.databaseMigrateOnStartup: true`). On app startup it converts async URLs to a sync driver for Alembic, applies pending revisions, and fails startup if migrations fail.

### SQLite / single replica (current default)

Use this for the simple PVC-backed SQLite setup. The application pod handles its own migrations on boot.

```yaml
config:
  databaseMigrateOnStartup: true

migration:
  enabled: false
```

What happens:

- the app container starts
- it runs `python -m app.db.migrate upgrade` during startup
- if migrations fail, the pod does not become ready

### External PostgreSQL / Helm-managed migration

Use this when you want migrations to run once per Helm install or upgrade, instead of in every app pod. Replicated mode requires this workflow:

```yaml
config:
  databaseMigrateOnStartup: false

migration:
  enabled: true
  schemaGate:
    enabled: true
```

What happens:

- Helm runs a hook Job that executes `python -m app.db.migrate upgrade`
- the app pod waits for the schema to be current before starting the main container
- the app container starts without running migrations itself

That mode uses the released `python -m app.db.migrate upgrade` command and a schema gate that is forward-compatible across image versions:

- on `1.8.3`, it falls back to looping on `python -m app.db.migrate check`
- on newer images that expose `wait-for-head`, it automatically prefers the native `wait-for-head` command

The hook-job mode is best suited to external database deployments. If you stay on SQLite, keep startup migration enabled.

## OAuth Callback via Ingress

To expose the OAuth callback through your ingress controller, enable both the OAuth Service and OAuth Ingress:

```yaml
config:
  oauthRedirectUri: "https://codex-lb.example.com/auth/callback"

service:
  oauth:
    enabled: true

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: codex-lb.example.com
      paths:
        - path: /
          pathType: Prefix
  oauth:
    enabled: true
    hosts:
      - host: codex-lb.example.com
        paths:
          - path: /auth/callback
            pathType: Exact
```

## Gateway API HTTPRoute Example

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: shared-gateway
      namespace: infra
  hostnames:
    - codex-lb.example.com
```

When `topology.mode=replicated`, the chart also renders a dedicated continuity `HTTPRoute` for the response-owner paths unless you disable `replication.continuity.enabled`.

## Continuity-aware response routing

Replicated mode treats long-lived response-owner flows differently from generic `/` traffic.

- the chart renders a dedicated continuity route for `/v1/responses` and `/backend-api/codex/responses`
- the replicated workload auto-advertises a per-pod internal handoff URL
- when using nginx ingress, the dedicated continuity ingress adds session-aware hash and retry annotations

Those features are intentionally tied to replicated mode so the chart does not imply multi-replica safety when the underlying topology is still single-pod.

## Flux Example

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: icoretech
  namespace: flux-system
spec:
  type: oci
  interval: 30m
  url: oci://ghcr.io/icoretech/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: codex-lb
  namespace: codex-lb
spec:
  interval: 5m
  chart:
    spec:
      chart: codex-lb
      version: ">=0.1.0"
      sourceRef:
        kind: HelmRepository
        name: icoretech
        namespace: flux-system
  values:
    envFrom:
      - secretRef:
          name: codex-lb-env
    encryptionKey:
      existingSecret:
        name: codex-lb-encryption
        key: fernet-key
```

## Configuration reference

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity. |
| config | object | `{"authBaseUrl":"https://auth.openai.com","databaseMigrateOnStartup":true,"databasePoolSize":15,"databaseUrl":"","firewallTrustProxyHeaders":false,"firewallTrustedProxyCidrs":"127.0.0.1/32,::1/128","imageInlineFetchEnabled":true,"modelRegistryEnabled":true,"oauthCallbackHost":"0.0.0.0","oauthCallbackPort":1455,"oauthRedirectUri":"http://localhost:1455/auth/callback","proxyRequestBudgetSeconds":600,"sessionBridgeInstanceId":"","sessionBridgeInstanceRing":"","streamIdleTimeoutSeconds":300,"upstreamBaseUrl":"https://chatgpt.com/backend-api","upstreamStreamTransport":"auto"}` | codex-lb application configuration mapped to CODEX_LB_* environment variables. |
| config.authBaseUrl | string | `"https://auth.openai.com"` | OpenAI OAuth base URL. |
| config.databaseMigrateOnStartup | bool | `true` | Run Alembic migrations on startup. |
| config.databasePoolSize | int | `15` | Database connection pool size. |
| config.databaseUrl | string | `""` | For secret-backed deployments, prefer envFrom/extraEnv with CODEX_LB_DATABASE_URL instead of setting this literal value. |
| config.firewallTrustProxyHeaders | bool | `false` | Trust X-Forwarded-For headers (set true when behind ingress/proxy). |
| config.firewallTrustedProxyCidrs | string | `"127.0.0.1/32,::1/128"` | Trusted proxy CIDRs (comma-separated). |
| config.imageInlineFetchEnabled | bool | `true` | Enable inline image fetching. |
| config.modelRegistryEnabled | bool | `true` | Enable model registry auto-fetching from upstream. |
| config.oauthCallbackHost | string | `"0.0.0.0"` | OAuth callback bind host. |
| config.oauthCallbackPort | int | `1455` | OAuth callback port. |
| config.oauthRedirectUri | string | `"http://localhost:1455/auth/callback"` | OAuth redirect URI (also enable service.oauth and ingress.oauth when exposing via Ingress). |
| config.proxyRequestBudgetSeconds | int | `600` | Max proxy request duration in seconds. |
| config.sessionBridgeInstanceId | string | `""` | Session bridge instance ID (defaults to hostname). |
| config.sessionBridgeInstanceRing | string | `""` | Session bridge instance ring (for multi-instance awareness). |
| config.streamIdleTimeoutSeconds | int | `300` | SSE stream idle timeout in seconds. |
| config.upstreamBaseUrl | string | `"https://chatgpt.com/backend-api"` | Upstream ChatGPT API base URL. |
| config.upstreamStreamTransport | string | `"auto"` | Stream transport mode: auto, http, or websocket. |
| deployment.progressDeadlineSeconds | int | `600` | Time in seconds for the Deployment controller to wait before marking a rollout failed. |
| deployment.strategy.type | string | `"Recreate"` | Deployment strategy for standalone mode. Recreate avoids RWO PVC multi-attach deadlocks during single-replica upgrades. |
| encryptionKey | object | `{"existingSecret":{"key":"","name":""},"path":"/home/app/.codex-lb/encryption.key"}` | Encryption key configuration. |
| encryptionKey.existingSecret | object | `{"key":"","name":""}` | Use an existing Kubernetes Secret for the encryption key instead of auto-generating. Replicated mode requires this so every pod shares the same key. |
| encryptionKey.existingSecret.key | string | `""` | Key within the secret. |
| encryptionKey.existingSecret.name | string | `""` | Secret name containing the encryption key. |
| encryptionKey.path | string | `"/home/app/.codex-lb/encryption.key"` | Path inside the container for the Fernet encryption key file. |
| envFrom | list | `[]` | Extra envFrom entries. |
| extraEnv | list | `[]` | Additional environment variables. |
| fullnameOverride | string | `""` | Override fully-qualified release name. |
| httpRoute.annotations | object | `{}` | HTTPRoute annotations. |
| httpRoute.enabled | bool | `false` | Enable Gateway API HTTPRoute. |
| httpRoute.hostnames | list | `[]` | Optional HTTPRoute hostnames. |
| httpRoute.matches | list | `[{"path":{"type":"PathPrefix","value":"/"}}]` | Match rules for HTTPRoute. |
| httpRoute.oauth.enabled | bool | `false` | Requires service.oauth.enabled=true. |
| httpRoute.oauth.hostnames | list | `[]` | Optional hostnames for OAuth HTTPRoute. |
| httpRoute.oauth.matches | list | `[{"path":{"type":"Exact","value":"/auth/callback"}}]` | Match rules for OAuth HTTPRoute callback path. |
| httpRoute.oauth.parentRefs | list | `[]` | ParentRefs for the OAuth HTTPRoute (inherits httpRoute.parentRefs if empty). |
| httpRoute.parentRefs | list | `[]` | ParentRefs for HTTPRoute (required when enabled). |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.repository | string | `"ghcr.io/soju06/codex-lb"` | Container image repository. |
| image.tag | string | `""` | Image tag override. Defaults to chart appVersion. |
| imagePullSecrets | list | `[]` | List of image pull secrets. |
| ingress.annotations | object | `{}` | Ingress annotations. For WebSocket support with nginx, set proxy-read-timeout, proxy-send-timeout, and proxy-http-version. |
| ingress.className | string | `""` | IngressClass name. |
| ingress.enabled | bool | `false` | Enable Ingress. |
| ingress.hosts | list | `[]` | Ingress hosts and paths. |
| ingress.oauth.annotations | object | `{}` | OAuth Ingress annotations. |
| ingress.oauth.className | string | `""` | IngressClass name for the OAuth Ingress (inherits ingress.className if empty). |
| ingress.oauth.enabled | bool | `false` | Requires service.oauth.enabled=true. |
| ingress.oauth.hosts | list | `[]` | OAuth Ingress hosts and paths. |
| ingress.oauth.tls | list | `[]` | OAuth Ingress TLS entries. |
| ingress.tls | list | `[]` | Ingress TLS entries. |
| livenessProbe.enabled | bool | `true` | Enable liveness probe. |
| livenessProbe.failureThreshold | int | `3` |  |
| livenessProbe.httpGet.path | string | `"/health"` | Liveness probe path. |
| livenessProbe.initialDelaySeconds | int | `10` |  |
| livenessProbe.periodSeconds | int | `10` |  |
| livenessProbe.successThreshold | int | `1` |  |
| livenessProbe.timeoutSeconds | int | `3` |  |
| migration.activeDeadlineSeconds | int | `300` | Maximum runtime for the migration Job in seconds. |
| migration.backoffLimit | int | `1` | Number of retries before the migration Job is marked failed. |
| migration.enabled | bool | `false` | Intended for PostgreSQL-style deployments where startup migration is disabled. Replicated mode requires this. |
| migration.hook.deletePolicy | string | `"before-hook-creation,hook-failed"` | Hook delete policy for the migration Job. |
| migration.hook.phases | string | `"pre-install,pre-upgrade"` | Hook phases for the migration Job. |
| migration.resources | object | `{}` | Resources for the migration Job and schema gate init container. |
| migration.schemaGate.enabled | bool | `false` | Add an init container that loops on `python -m app.db.migrate check` until schema is ready. |
| migration.schemaGate.intervalSeconds | int | `5` | Poll interval in seconds while waiting for schema readiness. |
| migration.schemaGate.timeoutSeconds | int | `120` | Maximum seconds the schema gate waits before failing the pod. |
| nameOverride | string | `""` | Override chart name. |
| nodeSelector | object | `{}` | Node selector. |
| persistence.accessModes | list | `["ReadWriteOnce"]` | PVC access modes. |
| persistence.annotations | object | `{}` | PVC annotations. |
| persistence.enabled | bool | `true` | Enable data persistence for codex-lb (SQLite DB, encryption key, backups) in standalone mode. |
| persistence.existingClaim | string | `""` | Existing PVC name to use instead of creating one. |
| persistence.mountPath | string | `"/home/app/.codex-lb"` | Mount path for codex-lb data. Keep this aligned with codex-lb's default Kubernetes data directory unless you also override the database URL. |
| persistence.size | string | `"5Gi"` | PVC size. |
| persistence.storageClass | string | `""` | PVC storage class. |
| persistence.volumeMode | string | `""` | PVC volume mode. |
| podAnnotations | object | `{}` | Pod annotations. |
| podLabels | object | `{}` | Pod labels. |
| podSecurityContext | object | `{"fsGroup":1000}` | Pod security context. Defaults ensure the PVC-mounted SQLite database stays writable for the non-root app user. |
| readinessProbe.enabled | bool | `true` | Enable readiness probe. |
| readinessProbe.failureThreshold | int | `3` |  |
| readinessProbe.httpGet.path | string | `"/health"` | Readiness probe path. |
| readinessProbe.initialDelaySeconds | int | `5` |  |
| readinessProbe.periodSeconds | int | `10` |  |
| readinessProbe.successThreshold | int | `1` |  |
| readinessProbe.timeoutSeconds | int | `3` |  |
| replicaCount | int | `1` | Number of replicas. Standalone mode is intentionally single-replica; replicated mode requires 2+ replicas. |
| replication.continuity.enabled | bool | `true` | Render a dedicated continuity route for response-owner traffic in replicated mode. |
| replication.continuity.nginx.configurationSnippet | string | `"set $codex_lb_continuity_key \"$http_authorization:$request_id\";\nif ($http_x_codex_session_id != \"\") {\n  set $codex_lb_continuity_key $http_x_codex_session_id;\n}\n"` | Nginx snippet that prefers x-codex-session-id and otherwise falls back to authorization + request id. |
| replication.continuity.nginx.enabled | bool | `true` | Add nginx continuity annotations to the dedicated response-owner ingress. |
| replication.continuity.nginx.hashBy | string | `"$codex_lb_continuity_key"` | Nginx variable used for continuity-aware hashing. |
| replication.continuity.nginx.retryOn | string | `"error timeout http_502 http_503 http_504 invalid_header"` | Retry policy for transient response-owner handoff failures. |
| replication.continuity.nginx.retryTries | int | `2` | Retry budget for the continuity ingress. |
| replication.continuity.pathType | string | `"Exact"` | Path match type for continuity routes. |
| replication.continuity.paths | list | `["/v1/responses","/backend-api/codex/responses"]` | Response-owner paths that should keep continuity-aware routing in replicated mode. |
| replication.disruptionBudget.enabled | bool | `true` | Create a PodDisruptionBudget in replicated mode. |
| replication.disruptionBudget.maxUnavailable | int | `1` | Max unavailable replicas for the replicated-mode PodDisruptionBudget. |
| replication.gracefulShutdown.preStopSleepSeconds | int | `15` | Seconds to sleep in the replicated-mode preStop hook after requesting drain. |
| replication.gracefulShutdown.terminationGracePeriodSeconds | int | `60` | Pod termination grace period in replicated mode. |
| replication.handoffAdvertiseUrl | string | `""` | Optional explicit owner-handoff base URL. Leave empty to auto-derive a per-pod internal address from the headless handoff Service. |
| resources | object | `{}` | Container resources. |
| securityContext | object | `{"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000}` | Container security context. Matches the upstream `app` user baked into the image. |
| service.annotations | object | `{}` | Service annotations. |
| service.externalTrafficPolicy | string | `nil` | External traffic policy. |
| service.loadBalancerIP | string | `nil` | Optional LoadBalancer IP. |
| service.loadBalancerSourceRanges | list | `[]` | Optional CIDRs allowed via LoadBalancer. |
| service.nodePort | string | `nil` | Optional nodePort when service.type is NodePort/LoadBalancer. |
| service.oauth.enabled | bool | `false` | Enable a separate Service for the OAuth callback port. |
| service.oauth.nodePort | string | `nil` | Optional nodePort for OAuth callback service. |
| service.oauth.port | int | `1455` | OAuth callback service port. |
| service.oauth.type | string | `"ClusterIP"` | OAuth callback service type. |
| service.port | int | `80` | Main API + dashboard service port. |
| service.targetPort | int | `2455` | Target container port for the main API. |
| service.type | string | `"ClusterIP"` | Service type. |
| serviceAccount.annotations | object | `{}` | Service account annotations. |
| serviceAccount.create | bool | `true` | Create a service account. |
| serviceAccount.name | string | `""` | Service account name. |
| tolerations | list | `[]` | Tolerations. |
| topology.clusterDomain | string | `"cluster.local"` | Kubernetes cluster domain suffix used when deriving per-pod internal handoff addresses in replicated mode. |
| topology.mode | string | `"standalone"` | Operating mode for this chart. `standalone` keeps the current SQLite/PVC-friendly Deployment path. `replicated` renders a StatefulSet plus an internal handoff Service and assumes external PostgreSQL. |
| volumeMounts | list | `[]` | Additional volume mounts. |
| volumes | list | `[]` | Additional volumes. |
