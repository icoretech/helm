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
| `replicaCount` | Number of replicas for the pgBouncer deployment | `1` |
| `updateStrategy` | Update strategy for the deployment | `{}` |
| `minReadySeconds` | Interval between discrete pods transitions | `0` |
| `revisionHistoryLimit` | Rollback limit | `10` |
| `imagePullSecrets` | Optional array of imagePullSecrets containing private registry credentials | `[]` |
| `image.registry` | Registry for the pgBouncer image | `""` |
| `image.repository` | Repository for the pgBouncer image | `ghcr.io/airflow-helm/pgbouncer` |
| `image.tag` | Tag for the pgBouncer image | `1.18.0-patch.1` |
| `image.pullPolicy` | Pull policy for the pgBouncer image | `IfNotPresent` |
| `service.type` | Service type | `ClusterIP` |
| `service.port` | Service port | `5432` |
| `podLabels` | Labels to add to the pod metadata | `{}` |
| `podAnnotations` | Annotations to add to the pod metadata | `{}` |
| `extraEnvs` | Additional environment variables to set | `[]` |
| `resources` | Pod resources for scheduling/limiting | `{}` |
| `nodeSelector` | Node labels for pod assignment | `{}` |
| `lifecycle` | Lifecycle hooks | `{}` |
| `tolerations` | Tolerations for pod assignment | `[]` |
| `affinity` | Affinity and anti-affinity | `{}` |
| `priorityClassName` | Priority of pods | `""` |
| `runtimeClassName` | Runtime class for pods | `""` |
| `config.adminUser` | Admin user for pgBouncer | `admin` |
| `config.adminPassword` | Admin password for pgBouncer | `undefined` |
| `config.authUser` | Auth user for pgBouncer | `undefined` |
| `config.authPassword` | Auth password for pgBouncer | `undefined` |
| `config.databases` | Database configuration | `{}` |
| `config.pgbouncer` | pgBouncer specific configuration | `{}` |
| `config.userlist` | User list for pgBouncer | `{}` |
| `extraContainers` | Additional containers to be added to the pods | `[]` |
| `extraInitContainers` | Containers which are run before the app containers are started | `[]` |
| `extraVolumeMounts` | Additional volumeMounts to the main container | `[]` |
| `extraVolumes` | Additional volumes to the pods | `[]` |
| `pgbouncerExporter.enabled` | Enable pgBouncer exporter | `false` |
| `pgbouncerExporter.port` | pgBouncer exporter port | `9127` |

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
      version: ">= 1.8.4"
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
        # max_client_conn: 500
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
