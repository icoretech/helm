# pgBouncer Helm Chart

This chart deploys a [pgBouncer](https://www.pgbouncer.org/) instance to your Kubernetes cluster via Helm.

## Prerequisites

- Kubernetes 1.20+
- Helm 3.10+

## Installing the Chart

To install the chart with the release name `my-pgbouncer`:

```bash
# OCI
helm install my-pgbouncer oci://ghcr.io/icoretech/charts/pgbouncer
```

```bash
helm repo add icoretech https://icoretech.github.io/helm
helm install my-pgbouncer icoretech/pgbouncer
```

This command deploys a pgBouncer instance with default configuration.

## Configuration

The following table lists the configurable parameters of the pgBouncer chart and their default values.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `replicaCount` | Number of pgBouncer replicas; adjust for scalability. | `1` |
| `updateStrategy` | Strategy for updating pods. Use `Recreate` or specify `RollingUpdate` settings. | `{}` |
| `minReadySeconds` | Seconds to wait before marking a pod as ready. Helps manage rollouts. | `0` |
| `revisionHistoryLimit` | Number of old ReplicaSets to retain for rollback. | `10` |
| `imagePullSecrets` | Secrets for accessing private image registries. Format: `[{"name": "mySecret"}]`. | `[]` |
| `image.registry` | Registry URL for the pgBouncer image. | `""` |
| `image.repository` | Image repository for pgBouncer. | `ghcr.io/icoretech/pgbouncer-docker` |
| `image.tag` | Specific image tag to use. | `1.23.1-fixed` |
| `image.pullPolicy` | Image pull policy. Options: `Always`, `Never`, `IfNotPresent`. | `IfNotPresent` |
| `service.type` | Kubernetes Service type (e.g., `ClusterIP`, `NodePort`). | `ClusterIP` |
| `service.port` | Port for the pgBouncer service. | `5432` |
| `podLabels` | Custom labels for pods. Format: `key: value`. | `{}` |
| `podAnnotations` | Annotations for pods, e.g., for Prometheus. | `{}` |
| `extraEnvs` | Extra environment variables for the pod. Format: `[{"name": "VAR", "value": "value"}]`. | `[]` |
| `resources` | CPU and memory resources for the container. Example: `limits: { cpu: "100m", memory: "200Mi" }`. | `{}` |
| `nodeSelector` | Node labels for pod assignment. Format: `key: value`. | `{}` |
| `lifecycle` | Custom lifecycle hooks. | `{}` |
| `tolerations` | Tolerations for pod scheduling. | `[]` |
| `affinity` | Pod affinity and anti-affinity rules. | `{}` |
| `priorityClassName` | Sets priority class for the pod. | `""` |
| `runtimeClassName` | Runtime class for pods (e.g., for using gVisor). | `""` |
| `config.adminUser` | Admin username required by pgBouncer. | `admin` |
| `config.adminPassword` | Admin password; use with a secret for security. | `undefined` |
| `config.authUser` | Auth user for client connections; set if different from `adminUser`. | `undefined` |
| `config.authPassword` | Password for the `authUser`. | `undefined` |
| `config.databases` | Database connection info. Format: `dbName: {host: "host", port: "port"}`. | `{}` |
| `config.pgbouncer` | pgBouncer-specific settings. Example: `pool_mode: transaction`. | `{}` |
| `extraContainers` | Additional containers in the pod. Useful for sidecars. | `[]` |
| `extraInitContainers` | Init containers to run before main containers start. | `[]` |
| `extraVolumeMounts` | Additional volume mounts for containers. | `[]` |
| `extraVolumes` | Additional volumes for the pod. Useful for configs or secrets. | `[]` |
| `pgbouncerExporter.enabled` | Enables pgBouncer metrics exporter for Prometheus. | `false` |
| `pgbouncerExporter.port` | Port for the metrics exporter. | `9127` |
| `pgbouncerExporter.podMonitor` | Create a PodMonitor resource for Prometheus scraping. Requires `pgbouncerExporter.enabled: true`. | `false` |
| `serviceAccount.create` | Whether to create a new service account. Set to `false` if using an existing one. | `true` |
| `serviceAccount.name` | The service account's name. Leave blank to auto-generate. | `""` |
| `serviceAccount.annotations` | Annotations for the service account. | `{}` |
| `podDisruptionBudget.enabled` | Enable PDB to ensure availability during disruptions. | `false` |


## Example using Flux

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: icoretech
spec:
  interval: 30m
  type: oci
  url: oci://ghcr.io/icoretech/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: pgbouncer
  namespace: default
spec:
  releaseName: pgbouncer
  chart:
    spec:
      chart: pgbouncer
      version: ">= 2.3.0"
      sourceRef:
        kind: HelmRepository
        name: icoretech
        namespace: flux-system
  interval: 3m0s
  install:
    remediation:
      retries: 3
  values:
    config:
      adminPassword: myadminpassword
      databases:
        mydb_production:
          host: postgresql
          port: 5432
      pgbouncer:
        server_tls_sslmode: prefer
        ignore_startup_parameters: extra_float_digits
        pool_mode: transaction
        auth_type: scram-sha-256
        max_client_conn: 8192
        max_db_connections: 200
        default_pool_size: 100
        log_connections: 1
        log_disconnections: 1
        log_pooler_errors: 1
        application_name_add_host: 1
        # verbose: 1
      userlist:
        # SELECT rolname, rolpassword FROM pg_authid;
        myuser: SCRAM-SHA-256$4096:xxxxx=
```
