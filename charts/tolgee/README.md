# Tolgee Helm Chart

Deploy [Tolgee Platform](https://tolgee.io/) on Kubernetes with optional bundled PostgreSQL (CloudPirates chart) or external PostgreSQL wiring.

## Features

- Tolgee upstream image defaults (`image.repository=tolgee/tolgee` with the default tag tracked in chart values)
- Optional bundled PostgreSQL dependency (`postgres.enabled=true`)
- External PostgreSQL mode with inline values or existing Secret refs
- Configurable persistence for Tolgee filesystem data (`/data` by default)
- Ingress and Gateway API `HTTPRoute` support
- Generic Tolgee/Spring property pass-through via dot-notation maps (`tolgee.config`, `tolgee.secretConfig`)

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
| database.waitForReady.image | string | `"busybox:1.37"` | Init container image used for DB readiness checks. |
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
| tolgee.authentication.userCanCreateOrganizations | string | `nil` | tolgee.authentication.user-can-create-organizations |
| tolgee.cache.enabled | string | `nil` | tolgee.cache.enabled |
| tolgee.cache.useRedis | string | `nil` | tolgee.cache.use-redis |
| tolgee.config | object | `{}` | Example: tolgee.authentication.google.client-id |
| tolgee.envFrom | list | `[]` | Additional envFrom refs. |
| tolgee.extraEnv | list | `[]` | Additional env vars. |
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
| tolgee.websocket.useRedis | string | `nil` | tolgee.websocket.use-redis |
