# Tolgee Helm Chart

Deploy [Tolgee Platform](https://tolgee.io/) on Kubernetes with optional bundled PostgreSQL (CloudPirates chart) or external PostgreSQL wiring.

## Features

- Tolgee upstream image defaults (`image.repository=tolgee/tolgee` with the default tag tracked in chart values)
- Optional bundled PostgreSQL dependency (`postgres.enabled=true`)
- External PostgreSQL mode with inline values or existing Secret refs
- Configurable persistence for Tolgee filesystem data (`/data` by default)
- Ingress and Gateway API `HTTPRoute` support
- Generic Tolgee/Spring property pass-through via dot-notation maps (`tolgee.config`, `tolgee.secretConfig`)
- OAuth 2.1 client registration, Azure Blob Storage, async pool sizing, and rate-limit concurrency controls

## Prerequisites

- Kubernetes 1.24+
- Helm 3.10+

## Install

```bash
helm repo add icoretech https://icoretech.github.io/helm
helm repo update
helm upgrade --install tolgee icoretech/tolgee \
  -n tolgee --create-namespace \
  --set tolgee.authentication.jwtSecret="replace-with-a-strong-secret-at-least-32-characters"
```

OCI:

```bash
helm upgrade --install tolgee oci://ghcr.io/icoretech/charts/tolgee \
  -n tolgee --create-namespace \
  --set tolgee.authentication.jwtSecret="replace-with-a-strong-secret-at-least-32-characters"
```

## External PostgreSQL Example

```yaml
postgres:
  enabled: false

database:
  external:
    enabled: true
    host: postgres.example.com
    port: 5432
    name: tolgee
    username: tolgee
    password: supersecret

tolgee:
  authentication:
    jwtSecret: "replace-with-a-strong-secret-at-least-32-characters"
```

## Existing Secret for External PostgreSQL

```yaml
postgres:
  enabled: false

database:
  external:
    enabled: true
    existingSecret:
      name: tolgee-db
      urlKey: SPRING_DATASOURCE_URL
      usernameKey: SPRING_DATASOURCE_USERNAME
      passwordKey: SPRING_DATASOURCE_PASSWORD
```

When using `database.external.existingSecret` without explicit host fields, disable startup wait:

```yaml
database:
  waitForReady:
    enabled: false
```

or set `database.external.host` so the initContainer can probe DB readiness.

## External PostgreSQL Values from Multiple Secrets

Use `database.external.extraEnv` for helper values that must be available before
Kubernetes expands `database.external.jdbcUrl`. Keep the `SPRING_DATASOURCE_*`
names owned by the chart through `jdbcUrl`/`jdbcUrlFrom`, `username`/`usernameFrom`,
and `password`/`passwordFrom`.

```yaml
postgres:
  enabled: false

database:
  external:
    enabled: true
    extraEnv:
      - name: AURORA_HOSTNAME
        valueFrom:
          secretKeyRef:
            name: tolgee-aurora
            key: hostname
      - name: TOLGEE_DB_NAME
        valueFrom:
          secretKeyRef:
            name: tolgee-db-creds
            key: database
    jdbcUrl: "jdbc:postgresql://$(AURORA_HOSTNAME):5432/$(TOLGEE_DB_NAME)?sslmode=require"
    usernameFrom:
      secretKeyRef:
        name: tolgee-db-creds
        key: username
    passwordFrom:
      secretKeyRef:
        name: tolgee-db-creds
        key: password
  waitForReady:
    enabled: false
```

## Sensitive Values via Secret Refs

Use the built-in `*Ref` fields when you want chart-managed env wiring without storing clear-text values in Helm values:

- `tolgee.authentication.jwtSecretRef`
- `tolgee.authentication.initialPasswordRef`
- `tolgee.smtp.passwordRef`
- `tolgee.fileStorage.s3.accessKeyRef`
- `tolgee.fileStorage.s3.secretKeyRef`
- `tolgee.fileStorage.azure.connectionStringRef`

## OAuth 2.1 and Reverse Proxies

Tolgee 3.220.0 introduced an OAuth 2.1 authorization server for the browser extension, CLI, and MCP. Set `tolgee.backEndUrl` to the public backend origin behind a reverse proxy. OAuth uses this URL as its issuer, falling back to `tolgee.frontEndUrl`; registering an OAuth client requires one of these URLs. Use an origin such as `https://tolgee.example.com`, without a path, query, or fragment. Do not set `server.forward-headers-strategy`; Tolgee uses the explicit backend URL instead.

Empty redirect URI lists leave the corresponding clients unregistered. Register only the exact URIs needed by your clients; prefer the loopback IP literal `127.0.0.1` for CLI callbacks.

```yaml
tolgee:
  frontEndUrl: https://tolgee.example.com
  backEndUrl: https://tolgee.example.com
  authentication:
    enabled: true
  oauth2:
    cliRedirectUris:
      - http://127.0.0.1:9876/callback
    accessTokenValidityMinutes: 30
    refreshTokenValidityDays: 30
```

The browser extension uses `tolgee.oauth2.browserExtensionRedirectUris`. Token and consent lifetimes, grant retention, and grant cleanup scheduling can also be configured under `tolgee.oauth2`; unset fields preserve upstream defaults.

Ingress or gateway routing must forward `/oauth2/*`, `/.well-known/*`, and `/mcp/*` to Tolgee when using these clients, in addition to the UI and `/v2/*` APIs. A single `/` prefix route covers these paths. Ensure any external authentication proxy permits OAuth discovery and token requests to reach Tolgee's own authentication layer.

## Azure Blob Storage

Tolgee 3.221.0 added Azure Blob Storage for application files. Create the Azure container before starting Tolgee and provide the storage account connection string through an existing Kubernetes Secret. Azure and S3 file storage cannot be enabled together.

```yaml
persistence:
  enabled: false

tolgee:
  fileStorage:
    azure:
      enabled: true
      containerName: tolgee-files
      connectionStringRef:
        name: tolgee-storage
        key: connection-string
```

`connectionStringRef` takes precedence over the inline `connectionString`. Disabling local persistence is appropriate when all application files use object storage; PostgreSQL persistence remains independent.

## Async Pools and Rate Limits

Tolgee 3.219.5 added explicit sizing for streaming and background thread pools. Leave `tolgee.async` fields unset to derive concurrency from the database pool: streaming uses one-third and background one-sixth of the connection pool, with a minimum of two threads each. Streaming responses hold a database connection for their entire duration, so leave capacity for ordinary requests and batch jobs.

This chart disables the application's embedded PostgreSQL autostart. Configure the external datasource pool through `spring.datasource.hikari.maximum-pool-size`, including when using the chart's separate bundled PostgreSQL dependency.

```yaml
tolgee:
  config:
    spring.datasource.hikari.maximum-pool-size: 30
  async:
    streaming:
      maxThreads: 6
      queueCapacity: 50
    background:
      maxThreads: 4
  rateLimits:
    lockWaitMs: 500
    maxConcurrentPerBucket: 50
```

Zero or negative `maxThreads` selects automatic sizing. A negative streaming `queueCapacity` selects automatic capacity; zero allows no queueing. Zero `keepAliveSeconds` disables idle thread expiry. The per-bucket concurrency cap applies per node; zero disables that cap. New chart fields default to `null` so upstream defaults remain effective.

## Multiple Replicas

Use shared PostgreSQL, shared Redis, and shared file storage before increasing `replicaCount` or enabling autoscaling. Redis must be enabled for both cache/rate-limit consistency and websocket event distribution; configuring a Redis hostname alone does not enable it. The same Redis client also supports MCP session recovery across replicas.

```yaml
replicaCount: 2
persistence:
  enabled: false
tolgee:
  cache:
    enabled: true
    useRedis: true
  websocket:
    useRedis: true
  config:
    spring.data.redis.host: redis.example.com
    spring.data.redis.port: 6379
  extraEnv:
    - name: SPRING_DATA_REDIS_PASSWORD
      valueFrom:
        secretKeyRef:
          name: tolgee-redis
          key: password
```

Combine this fragment with S3 or Azure configuration, or use a shared filesystem PVC with `ReadWriteMany` access. Disabling persistence without shared object storage leaves each replica with its own ephemeral files.

## Release Compatibility

The configuration above was checked against Tolgee 3.226.3. The application image is tracked automatically. Upstream now uses Spring Boot 4 and Java 25; the application port, `/data` mount, and `/actuator/health` endpoint remain compatible with this chart.

The deprecated embedded PostgreSQL server is already disabled by this chart. The optional CloudPirates PostgreSQL dependency is a separate service and is unaffected by that deprecation. Remove `tolgee.cache.clean-on-startup` from custom configuration if present; upstream replaced that setting with automatic cache fingerprinting. The upstream slim Dockerfile is for local builds and its image tag is not published.

## Per-Organization SSO Internal URLs

Tolgee rejects loopback, private, link-local, multicast, and wildcard SSO provider URLs by default. Set `tolgee.authentication.ssoOrganizations.allowLocalAddresses=true` only when a self-hosted per-organization SSO provider intentionally lives on a trusted internal network.

## Webhook Internal URLs

Tolgee rejects loopback, private, link-local, multicast, and wildcard webhook target URLs by default. Set `tolgee.webhook.allowLocalAddresses=true` only for local development or when webhook targets intentionally live on a trusted internal network; this weakens SSRF protection for users who can configure webhooks.

## Registration Email Controls

Tolgee blocks disposable email domains and duplicate subaddress aliases for new registrations by default. Use `tolgee.authentication.blockDisposableEmails`, `tolgee.authentication.blockEmailAliases`, `tolgee.authentication.blockedEmailDomains`, and `tolgee.authentication.allowedEmailDomains` only when the deployment needs to override those defaults.

## Gateway API HTTPRoute Example

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: shared-gateway
      namespace: infra
  hostnames:
    - tolgee.example.com
```

## Metrics and ServiceMonitor

`metrics.serviceMonitor.enabled` requires Prometheus Operator CRDs (`monitoring.coreos.com/v1`) in the cluster.

```yaml
metrics:
  enabled: true
  path: /actuator/prometheus
  port: http
  serviceMonitor:
    enabled: true
    namespace: monitoring
    additionalLabels:
      release: kube-prometheus-stack
```

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
  name: tolgee
  namespace: tolgee
spec:
  interval: 5m
  chart:
    spec:
      chart: tolgee
      version: ">=0.1.0"
      sourceRef:
        kind: HelmRepository
        name: icoretech
        namespace: flux-system
  values:
    postgres:
      enabled: true
    tolgee:
      authentication:
        jwtSecretRef:
          name: tolgee-auth
          key: jwtSecret
```

## Configuration reference

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity. |
| autoscaling.enabled | bool | `false` | Enable HPA. |
| autoscaling.maxReplicas | int | `10` | Maximum replicas. |
| autoscaling.minReplicas | int | `1` | Minimum replicas. |
| autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage. |
| autoscaling.targetMemoryUtilizationPercentage | string | `nil` | Target memory utilization percentage. |
| database.external.enabled | bool | `false` | Enable external PostgreSQL mode. When enabled, set postgres.enabled=false. |
| database.external.existingSecret.name | string | `""` | Existing secret containing SPRING_DATASOURCE_* values. |
| database.external.existingSecret.passwordKey | string | `"SPRING_DATASOURCE_PASSWORD"` | Key for DB password. |
| database.external.existingSecret.urlKey | string | `"SPRING_DATASOURCE_URL"` | Key for JDBC URL. |
| database.external.existingSecret.usernameKey | string | `"SPRING_DATASOURCE_USERNAME"` | Key for DB username. |
| database.external.extraEnv | list | `[]` | Extra env vars rendered before SPRING_DATASOURCE_* for external DB URL expansion. |
| database.external.host | string | `""` | External PostgreSQL host. |
| database.external.jdbcUrl | string | `""` | Full external JDBC URL override. |
| database.external.jdbcUrlFrom | object | `{}` | Kubernetes valueFrom source for SPRING_DATASOURCE_URL. |
| database.external.name | string | `"tolgee"` | External PostgreSQL database name. |
| database.external.password | string | `""` | External PostgreSQL password. |
| database.external.passwordFrom | object | `{}` | Kubernetes valueFrom source for SPRING_DATASOURCE_PASSWORD. |
| database.external.port | int | `5432` | External PostgreSQL port. |
| database.external.username | string | `""` | External PostgreSQL username. |
| database.external.usernameFrom | object | `{}` | Kubernetes valueFrom source for SPRING_DATASOURCE_USERNAME. |
| database.internal.port | int | `5432` | Internal PostgreSQL service port. |
| database.internal.serviceName | string | `""` | Override internal PostgreSQL service name (defaults to <release>-postgres). |
| database.jdbcParameters | string | `"reWriteBatchedInserts=true"` | Extra JDBC query parameters (without leading ?), e.g. key1=value1&key2=value2. |
| database.sslMode | string | `"disable"` | SSL mode appended to JDBC URL. |
| database.waitForReady.enabled | bool | `true` | Wait for PostgreSQL TCP readiness before starting Tolgee. |
| database.waitForReady.image | string | `"busybox:1.38"` | Init container image used for DB readiness checks. |
| database.waitForReady.imagePullPolicy | string | `"IfNotPresent"` | Init container image pull policy. |
| database.waitForReady.periodSeconds | int | `2` | Poll interval in seconds. |
| database.waitForReady.timeoutSeconds | int | `180` | Max seconds to wait for DB readiness. |
| deployment.progressDeadlineSeconds | int | `1800` | Time in seconds for the Deployment controller to wait before marking a rollout failed. |
| deployment.strategy.type | string | `"Recreate"` | Deployment strategy. `Recreate` avoids RWO PVC multi-attach deadlocks during single-replica upgrades. |
| fullnameOverride | string | `""` | Override fully-qualified release name. |
| httpRoute.annotations | object | `{}` | HTTPRoute annotations. |
| httpRoute.enabled | bool | `false` | Enable Gateway API HTTPRoute. |
| httpRoute.hostnames | list | `[]` | Optional HTTPRoute hostnames. |
| httpRoute.matches | list | `[{"path":{"type":"PathPrefix","value":"/"}}]` | Match rules for HTTPRoute. |
| httpRoute.parentRefs | list | `[]` | ParentRefs for HTTPRoute (required when enabled). |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.repository | string | `"tolgee/tolgee"` | Tolgee container repository. |
| image.tag | string | `""` | Image tag override. Defaults to chart appVersion. |
| imagePullSecrets | list | `[]` | List of image pull secrets. |
| ingress.annotations | object | `{}` | Ingress annotations. |
| ingress.className | string | `""` | IngressClass name. |
| ingress.enabled | bool | `false` | Enable Ingress. |
| ingress.hosts | list | `[]` | Ingress hosts and paths. |
| ingress.tls | list | `[]` | Ingress TLS entries. |
| livenessProbe.enabled | bool | `true` | Enable liveness probe. |
| livenessProbe.failureThreshold | int | `6` |  |
| livenessProbe.httpGet.path | string | `"/actuator/health"` | Liveness probe path. |
| livenessProbe.initialDelaySeconds | int | `30` |  |
| livenessProbe.periodSeconds | int | `10` |  |
| livenessProbe.successThreshold | int | `1` |  |
| livenessProbe.timeoutSeconds | int | `3` |  |
| metrics.enabled | bool | `false` | Enable Prometheus metrics scraping hints and ServiceMonitor wiring. |
| metrics.path | string | `"/actuator/prometheus"` | HTTP path exposing Prometheus metrics from Tolgee. |
| metrics.port | string | `"http"` | Scrape port for metrics. Use service port name (e.g. http) or numeric target port. |
| metrics.serviceMonitor.additionalLabels | object | `{}` | Additional labels on ServiceMonitor (e.g. release label for kube-prometheus-stack). |
| metrics.serviceMonitor.annotations | object | `{}` | Additional annotations on ServiceMonitor. |
| metrics.serviceMonitor.enabled | bool | `false` | Enable ServiceMonitor resource for Prometheus Operator. |
| metrics.serviceMonitor.honorLabels | bool | `false` | Preserve labels from scraped targets. |
| metrics.serviceMonitor.interval | string | `"30s"` | Prometheus scrape interval. |
| metrics.serviceMonitor.jobLabel | string | `""` | Optional ServiceMonitor jobLabel. |
| metrics.serviceMonitor.metricRelabelings | list | `[]` | Metric relabeling configs for scraped samples. |
| metrics.serviceMonitor.namespace | string | `""` | Optional namespace where ServiceMonitor is created. Empty uses release namespace. |
| metrics.serviceMonitor.podTargetLabels | list | `[]` | Optional pod labels copied onto ingested samples. |
| metrics.serviceMonitor.relabelings | list | `[]` | Relabeling configs for target discovery. |
| metrics.serviceMonitor.scheme | string | `"http"` | Scrape scheme. |
| metrics.serviceMonitor.scrapeTimeout | string | `"10s"` | Prometheus scrape timeout. |
| metrics.serviceMonitor.targetLabels | list | `[]` | Optional labels from Service copied onto ingested samples. |
| metrics.serviceMonitor.tlsConfig | object | `{}` | TLS config for scrape endpoint. |
| nameOverride | string | `""` | Override chart name. |
| nodeSelector | object | `{}` | Node selector. |
| persistence.accessModes | list | `["ReadWriteOnce"]` | PVC access modes. |
| persistence.annotations | object | `{}` | PVC annotations. |
| persistence.enabled | bool | `true` | Enable data persistence for Tolgee filesystem storage. |
| persistence.existingClaim | string | `""` | Existing PVC name to use instead of creating one. |
| persistence.mountPath | string | `"/data"` | Mount path for Tolgee data. |
| persistence.size | string | `"10Gi"` | PVC size. |
| persistence.storageClass | string | `""` | PVC storage class. |
| persistence.volumeMode | string | `""` | PVC volume mode. |
| podAnnotations | object | `{}` | Pod annotations. |
| podLabels | object | `{}` | Pod labels. |
| podSecurityContext | object | `{}` | Pod security context. |
| postgres.auth.database | string | `"tolgee"` |  |
| postgres.auth.password | string | `"tolgee"` |  |
| postgres.auth.username | string | `"tolgee"` |  |
| postgres.enabled | bool | `true` |  |
| postgres.persistence.enabled | bool | `true` |  |
| postgres.persistence.size | string | `"8Gi"` |  |
| readinessProbe.enabled | bool | `true` | Enable readiness probe. |
| readinessProbe.failureThreshold | int | `6` |  |
| readinessProbe.httpGet.path | string | `"/actuator/health"` | Readiness probe path. |
| readinessProbe.initialDelaySeconds | int | `10` |  |
| readinessProbe.periodSeconds | int | `10` |  |
| readinessProbe.successThreshold | int | `1` |  |
| readinessProbe.timeoutSeconds | int | `3` |  |
| replicaCount | int | `1` | Number of Tolgee replicas. |
| resources | object | `{}` | Container resources. |
| securityContext | object | `{}` | Container security context. |
| service.annotations | object | `{}` | Service annotations. |
| service.externalTrafficPolicy | string | `nil` | External traffic policy. |
| service.loadBalancerIP | string | `nil` | Optional LoadBalancer IP. |
| service.loadBalancerSourceRanges | list | `[]` | Optional CIDRs allowed via LoadBalancer. |
| service.nodePort | string | `nil` | Optional nodePort when service.type is NodePort/LoadBalancer. |
| service.port | int | `80` | Service port. |
| service.targetPort | int | `8080` | Target container port. |
| service.type | string | `"ClusterIP"` | Service type. |
| serviceAccount.annotations | object | `{}` | Service account annotations. |
| serviceAccount.create | bool | `true` | Create a service account. |
| serviceAccount.name | string | `""` | Service account name. |
| tolerations | list | `[]` | Tolerations. |
| tolgee.async.background.keepAliveSeconds | int | `nil` | Idle background thread lifetime in seconds. Zero keeps core threads alive; null preserves the application default. |
| tolgee.async.background.maxThreads | int | `nil` | Maximum background threads. Null preserves the application default; zero or negative derives from the database pool. |
| tolgee.async.streaming.keepAliveSeconds | int | `nil` | Idle streaming thread lifetime in seconds. Zero keeps core threads alive; null preserves the application default. |
| tolgee.async.streaming.maxThreads | int | `nil` | Maximum streaming threads. Null preserves the application default; zero or negative derives from the database pool. Keep below the database connection pool size. |
| tolgee.async.streaming.queueCapacity | int | `nil` | Streaming queue capacity. Zero disables queuing; negative derives capacity; null preserves the application default. |
| tolgee.authentication.allowedEmailDomains | list | `[]` | tolgee.authentication.allowed-email-domains |
| tolgee.authentication.blockDisposableEmails | string | `nil` | tolgee.authentication.block-disposable-emails |
| tolgee.authentication.blockEmailAliases | string | `nil` | tolgee.authentication.block-email-aliases |
| tolgee.authentication.blockedEmailDomains | list | `[]` | tolgee.authentication.blocked-email-domains |
| tolgee.authentication.createDemoForInitialUser | string | `nil` | tolgee.authentication.create-demo-for-initial-user |
| tolgee.authentication.enabled | string | `nil` | tolgee.authentication.enabled |
| tolgee.authentication.initialPassword | string | `""` | tolgee.authentication.initial-password |
| tolgee.authentication.initialPasswordRef.key | string | `""` | Secret key for initial password. |
| tolgee.authentication.initialPasswordRef.name | string | `""` | Existing secret containing tolgee.authentication.initial-password. |
| tolgee.authentication.initialUsername | string | `""` | tolgee.authentication.initial-username |
| tolgee.authentication.jwtSecret | string | `"replace-with-a-strong-secret-at-least-32-characters"` | tolgee.authentication.jwt-secret |
| tolgee.authentication.jwtSecretRef.key | string | `""` | Secret key for jwt secret. |
| tolgee.authentication.jwtSecretRef.name | string | `""` | Existing secret containing tolgee.authentication.jwt-secret. |
| tolgee.authentication.nativeEnabled | string | `nil` | tolgee.authentication.native-enabled |
| tolgee.authentication.needsEmailVerification | string | `nil` | tolgee.authentication.needs-email-verification |
| tolgee.authentication.registrationsAllowed | string | `nil` | tolgee.authentication.registrations-allowed |
| tolgee.authentication.ssoOrganizations.allowLocalAddresses | string | `nil` | tolgee.authentication.sso-organizations.allow-local-addresses. Enables internal/private SSO provider URLs; keep null/false unless the IdP is deliberately reachable only on a trusted internal network. |
| tolgee.authentication.userCanCreateOrganizations | string | `nil` | tolgee.authentication.user-can-create-organizations |
| tolgee.backEndUrl | string | `""` | Public backend URL used for OAuth issuer and endpoint discovery. Empty preserves Tolgee's URL resolution. |
| tolgee.cache.enabled | string | `nil` | tolgee.cache.enabled |
| tolgee.cache.useRedis | string | `nil` | tolgee.cache.use-redis |
| tolgee.config | object | `{}` | Example: tolgee.authentication.google.client-id |
| tolgee.envFrom | list | `[]` | Additional envFrom refs. |
| tolgee.extraEnv | list | `[]` | Additional env vars. |
| tolgee.fileStorage.azure.connectionString | string | `""` | Azure Storage connection string. Prefer connectionStringRef for credentials. |
| tolgee.fileStorage.azure.connectionStringRef.key | string | `""` | Secret key for the Azure connection string. |
| tolgee.fileStorage.azure.connectionStringRef.name | string | `""` | Existing secret containing the Azure connection string; takes priority over the inline value. |
| tolgee.fileStorage.azure.containerName | string | `""` | Existing Azure Blob Storage container name. |
| tolgee.fileStorage.azure.enabled | bool | `false` | Enable Azure Blob Storage. Cannot be enabled together with S3. |
| tolgee.fileStorage.fsDataPath | string | `"/data"` | tolgee.file-storage.fs-data-path |
| tolgee.fileStorage.s3.accessKey | string | `""` | tolgee.file-storage.s3.access-key |
| tolgee.fileStorage.s3.accessKeyRef.key | string | `""` | Secret key for S3 access key. |
| tolgee.fileStorage.s3.accessKeyRef.name | string | `""` | Existing secret containing tolgee.file-storage.s3.access-key. |
| tolgee.fileStorage.s3.bucketName | string | `""` | tolgee.file-storage.s3.bucket-name |
| tolgee.fileStorage.s3.enabled | bool | `false` | tolgee.file-storage.s3.enabled |
| tolgee.fileStorage.s3.endpoint | string | `""` | tolgee.file-storage.s3.endpoint |
| tolgee.fileStorage.s3.path | string | `""` | tolgee.file-storage.s3.path |
| tolgee.fileStorage.s3.secretKey | string | `""` | tolgee.file-storage.s3.secret-key |
| tolgee.fileStorage.s3.secretKeyRef.key | string | `""` | Secret key for S3 secret key. |
| tolgee.fileStorage.s3.secretKeyRef.name | string | `""` | Existing secret containing tolgee.file-storage.s3.secret-key. |
| tolgee.fileStorage.s3.signingRegion | string | `""` | tolgee.file-storage.s3.signing-region |
| tolgee.frontEndUrl | string | `""` | Public frontend URL (recommended for secure link generation). |
| tolgee.oauth2.accessTokenValidityMinutes | int | `nil` | OAuth access token lifetime in minutes. Null preserves the application default. |
| tolgee.oauth2.authorizationCodeValiditySeconds | int | `nil` | Authorization code lifetime in seconds. Null preserves the application default. |
| tolgee.oauth2.browserExtensionRedirectUris | list | `[]` | Exact browser extension redirect URIs. Empty leaves this OAuth client unregistered. |
| tolgee.oauth2.cliRedirectUris | list | `[]` | CLI loopback redirect URIs. Configure only when CLI OAuth login is needed; prefer a loopback IP literal. |
| tolgee.oauth2.consentValiditySeconds | int | `nil` | Pending consent lifetime in seconds. Null preserves the application default. |
| tolgee.oauth2.grantCleanupCron | string | `""` | Grant cleanup schedule in Spring six-field cron format. Empty preserves the application default. |
| tolgee.oauth2.grantRetentionDays | int | `nil` | Retention of spent grants after credential expiry in days. Null preserves the application default. |
| tolgee.oauth2.refreshTokenValidityDays | int | `nil` | OAuth refresh token lifetime in days, restarted on refresh. Null preserves the application default. |
| tolgee.rateLimits.lockWaitMs | int | `nil` | Maximum wait for a rate-limit bucket lock in milliseconds. Null preserves the application default. |
| tolgee.rateLimits.maxConcurrentPerBucket | int | `nil` | Concurrent requests per rate-limit bucket per node. Zero disables the cap; null preserves the application default. |
| tolgee.secretConfig | object | `{}` | Additional secret Tolgee/Spring properties in dot notation. |
| tolgee.smtp.auth | string | `nil` | tolgee.smtp.auth |
| tolgee.smtp.from | string | `""` | tolgee.smtp.from |
| tolgee.smtp.host | string | `""` | tolgee.smtp.host |
| tolgee.smtp.password | string | `""` | tolgee.smtp.password |
| tolgee.smtp.passwordRef.key | string | `""` | Secret key for SMTP password. |
| tolgee.smtp.passwordRef.name | string | `""` | Existing secret containing tolgee.smtp.password. |
| tolgee.smtp.port | int | `25` | tolgee.smtp.port |
| tolgee.smtp.sslEnabled | string | `nil` | tolgee.smtp.ssl-enabled |
| tolgee.smtp.tlsEnabled | string | `nil` | tolgee.smtp.tls-enabled |
| tolgee.smtp.tlsRequired | string | `nil` | tolgee.smtp.tls-required |
| tolgee.smtp.username | string | `""` | tolgee.smtp.username |
| tolgee.telemetry.enabled | string | `nil` | tolgee.telemetry.enabled |
| tolgee.telemetry.server | string | `""` | tolgee.telemetry.server |
| tolgee.webhook.allowLocalAddresses | string | `nil` | tolgee.webhook.allow-local-addresses. Enables internal/private webhook target URLs; keep null/false unless webhook targets are deliberately reachable only on a trusted internal network. |
| tolgee.websocket.useRedis | string | `nil` | tolgee.websocket.use-redis |
