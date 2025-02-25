# PgBouncer Helm Chart

This chart deploys a [PgBouncer](https://www.pgbouncer.org/) instance to your Kubernetes cluster via Helm.

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

This command deploys a PgBouncer instance with default configuration.

## Configuration

The following table lists the configurable parameters of the PgBouncer chart and their default values.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | See Kubernetes docs on affinity rules. |
| args | list | `[]` | Override the default container arguments. |
| command | list | `[]` | Override the default container command (entrypoint). |
| config.adminPassword | string | `nil` | If no existingAdminSecret is used, this admin password is placed in a new Secret. |
| config.adminPasswordKey | string | `"adminPassword"` | The key in the existingAdminSecret that corresponds to the admin password. |
| config.adminUser | string | `"admin"` | If no existingAdminSecret is used, this admin username is placed in a new Secret. |
| config.adminUserKey | string | `"adminUser"` | The key in the existingAdminSecret that corresponds to the admin username. |
| config.authPassword | string | `nil` | Password for the authUser above, if used. |
| config.authUser | string | `nil` | If set, PgBouncer will use this user to authenticate client connections. |
| config.databases | object | `{}` | Mapping of database names to connection parameters. E.g.: mydb: host=postgresql port=5432 |
| config.existingAdminSecret | string | `""` | If set, skip creating a new secret for admin credentials, and reference this existing Secret name instead. |
| config.existingUserlistSecret | string | `""` | Reference to an existing Secret that contains a userlist.txt file, with entries for other users/passwords. |
| config.pgbouncer | object | `{}` | Additional PgBouncer parameters (e.g. auth_type, pool_mode). |
| config.userlist | object | `{}` | if existingUserlistSecret isn't used. |
| extraContainers | list | `[]` | Extra containers to run within the PgBouncer pod. |
| extraEnvs | list | `[]` | Additional environment variables to set in the PgBouncer container. |
| extraInitContainers | list | `[]` | Init containers to run before the PgBouncer container starts. |
| extraVolumeMounts | list | `[]` | Additional volume mounts for the main PgBouncer container. |
| extraVolumes | list | `[]` | Additional volumes for the PgBouncer pod. |
| fullnameOverride | string | `""` | Completely overrides the generated name. If set, takes precedence over nameOverride and chart name. |
| image.pullPolicy | string | `"IfNotPresent"` | Container image pull policy: Always, IfNotPresent, or Never |
| image.registry | string | `""` | Container image registry |
| image.repository | string | `"ghcr.io/icoretech/pgbouncer-docker"` | Container image repository |
| image.tag | string | `"1.24.0"` | Container image tag |
| imagePullSecrets | list | `[]` | Array of imagePullSecrets to use for pulling private images. |
| lifecycle | object | `{}` | See Kubernetes docs on lifecycle hooks. |
| minReadySeconds | int | `0` | Minimum number of seconds for which a newly created pod should be ready without crashing, before being considered available. |
| nameOverride | string | `""` | Overrides the chart name for resources. If set, takes precedence over the chart's name. |
| nodeSelector | object | `{}` | Node labels for pod assignment. |
| pgbouncerExporter.enabled | bool | `false` | Enable or disable the PgBouncer exporter sidecar container. |
| pgbouncerExporter.image.pullPolicy | string | `"IfNotPresent"` | Exporter image pull policy |
| pgbouncerExporter.image.registry | string | `""` | Exporter image registry |
| pgbouncerExporter.image.repository | string | `"prometheuscommunity/pgbouncer-exporter"` | Exporter image repository |
| pgbouncerExporter.image.tag | string | `"v0.10.2"` | Exporter image tag |
| pgbouncerExporter.log.format | string | `"logfmt"` | Exporter log format (logfmt or json) |
| pgbouncerExporter.log.level | string | `"info"` | Exporter log level (debug, info, warn, error) |
| pgbouncerExporter.podMonitor | bool | `false` | Whether to create a PodMonitor for scraping metrics (Prometheus Operator). |
| pgbouncerExporter.port | int | `9127` | The container port for the exporter. |
| pgbouncerExporter.resources | object | `{"limits":{"cpu":"250m","memory":"150Mi"},"requests":{"cpu":"30m","memory":"40Mi"}}` | Resource requests and limits for the exporter container. |
| pgbouncerExporter.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":65534,"runAsNonRoot":true,"runAsUser":65534}` | Pod security context for the exporter container. |
| podAnnotations | object | `{}` | Additional annotations to add to each PgBouncer pod. |
| podDisruptionBudget | object | `{"enabled":false,"maxUnavailable":null,"minAvailable":null}` | Pod Disruption Budget configuration. |
| podDisruptionBudget.enabled | bool | `false` | If true, create a PDB to protect PgBouncer pods from voluntary disruptions. |
| podLabels | object | `{}` | Additional labels to add to each PgBouncer pod. |
| priorityClassName | string | `""` | Priority class for PgBouncer pods (for scheduling priority). |
| replicaCount | int | `1` | Number of replicas for the PgBouncer Deployment (see Kubernetes docs for Deployments). |
| resources | object | `{}` | See Kubernetes docs on managing container resources. |
| revisionHistoryLimit | int | `10` | How many old ReplicaSets to retain for rollbacks. |
| runtimeClassName | string | `""` | Runtime class for the PgBouncer pods (e.g. gvisor). |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":70,"runAsNonRoot":true,"runAsUser":70}` | Pod security context for the main PgBouncer container. By default, this forces the container to run without root privileges and with a read-only root filesystem: |
| service.port | int | `5432` | The service port for PgBouncer. |
| service.type | string | `"ClusterIP"` | Service type (e.g. ClusterIP, NodePort, LoadBalancer). |
| serviceAccount.annotations | object | `{}` | Annotations for the created ServiceAccount. |
| serviceAccount.name | string | `""` | Creates a new ServiceAccount if this is empty. |
| terminationGracePeriodSeconds | int | `30` | Time (in seconds) to allow graceful shutdown before force-terminating the container. |
| tolerations | list | `[]` | See Kubernetes docs on taints and tolerations. |
| updateStrategy | object | `{}` | The update strategy to apply to the Deployment (e.g. Recreate or RollingUpdate). |

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
      version: ">= 2.4.0"
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
        ignore_startup_parameters: search_path,extra_float_digits
        pool_mode: transaction
        auth_type: scram-sha-256
        max_client_conn: 8192
        max_db_connections: 200
        default_pool_size: 100
        log_connections: 1
        log_disconnections: 1
        log_pooler_errors: 1
        application_name_add_host: 1
        max_prepared_statements: 4000
        # verbose: 1
      userlist:
        # SELECT rolname, rolpassword FROM pg_authid;
        myuser: SCRAM-SHA-256$4096:xxxxx=
```
