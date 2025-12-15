<p align="center">
  <img src="https://i.imgur.com/dPL9YEz.png" height="400">
</p>

# Airbroke Helm Chart

This Helm chart deploys [Airbroke](https://airbroke.icorete.ch), a modern, React-based open source error catcher web application.

## Prerequisites

- Kubernetes 1.20+
- Helm 3.10+
- Postgres 15+ Database ready to use

## Installing the Chart

To install the chart with the release name `my-airbroke`:

```console
# OCI
helm install my-airbroke oci://ghcr.io/icoretech/charts/airbroke
```

```console
helm repo add icoretech https://icoretech.github.io/helm
helm install my-airbroke icoretech/airbroke
```

Please remember to set at least the `database.url` and `database.migrations_url` values. Continue reading for further details.

## Database

The `database.url` and `database.migrations_url` values must be set to the connection string of your PostgreSQL database.

## Configuration

The following table lists the configurable parameters of the Airbroke chart and their default values.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| database.enable_migration | bool | `true` |  |
| database.migrations_url | string | `""` |  |
| database.url | string | `""` |  |
| fullnameOverride | string | `""` |  |
| nameOverride | string | `""` |  |
| pgbouncer.config.adminPassword | string | `"airbroke"` |  |
| pgbouncer.config.databases.airbroke_production.host | string | `"postgres-postgresql.postgres.svc.cluster.local"` |  |
| pgbouncer.config.databases.airbroke_production.port | int | `5432` |  |
| pgbouncer.config.pgbouncer.application_name_add_host | int | `1` |  |
| pgbouncer.config.pgbouncer.auth_type | string | `"scram-sha-256"` |  |
| pgbouncer.config.pgbouncer.default_pool_size | int | `100` |  |
| pgbouncer.config.pgbouncer.ignore_startup_parameters | string | `"extra_float_digits"` |  |
| pgbouncer.config.pgbouncer.log_connections | int | `1` |  |
| pgbouncer.config.pgbouncer.log_disconnections | int | `1` |  |
| pgbouncer.config.pgbouncer.log_pooler_errors | int | `1` |  |
| pgbouncer.config.pgbouncer.max_client_conn | int | `8192` |  |
| pgbouncer.config.pgbouncer.max_db_connections | int | `200` |  |
| pgbouncer.config.pgbouncer.pool_mode | string | `"transaction"` |  |
| pgbouncer.config.userlist.airbroke_production | string | `"SCRAM-SHA-256$xxxxxx="` |  |
| pgbouncer.enabled | bool | `false` |  |
| web.affinity | object | `{}` |  |
| web.cachePersistentVolume.accessModes[0] | string | `"ReadWriteOnce"` |  |
| web.cachePersistentVolume.annotations | object | `{}` |  |
| web.cachePersistentVolume.enabled | bool | `false` |  |
| web.cachePersistentVolume.existingClaim | string | `""` |  |
| web.cachePersistentVolume.mountPath | string | `"/app/.next/cache"` |  |
| web.cachePersistentVolume.size | string | `"1Gi"` |  |
| web.cachePersistentVolume.storageClass | string | `""` |  |
| web.cachePersistentVolume.volumeMode | string | `""` |  |
| web.extraEnvs | list | `[]` |  |
| web.hpa.cpu | string | `nil` |  |
| web.hpa.enabled | bool | `false` |  |
| web.hpa.maxReplicas | int | `10` |  |
| web.hpa.memory | string | `nil` |  |
| web.hpa.requests | string | `nil` |  |
| web.image | string | `"ghcr.io/icoretech/airbroke:1.1.81"` |  |
| web.imagePullPolicy | string | `"IfNotPresent"` |  |
| web.imagePullSecrets | string | `""` |  |
| web.ingress.annotations | object | `{}` |  |
| web.ingress.enabled | bool | `false` |  |
| web.ingress.hosts | list | `[]` |  |
| web.ingress.ingressClassName | string | `"nginx"` |  |
| web.ingress.tls | list | `[]` |  |
| web.livenessProbe.enabled | bool | `true` |  |
| web.livenessProbe.failureThreshold | int | `2` |  |
| web.livenessProbe.httpGet.endpoint | string | `"/api/hc?source=livenessProbe"` |  |
| web.livenessProbe.httpGet.httpHeaders | list | `[]` |  |
| web.livenessProbe.initialDelaySeconds | int | `0` |  |
| web.livenessProbe.periodSeconds | int | `10` |  |
| web.livenessProbe.successThreshold | int | `1` |  |
| web.livenessProbe.timeoutSeconds | int | `5` |  |
| web.nodeSelector | object | `{}` |  |
| web.readinessProbe.enabled | bool | `true` |  |
| web.readinessProbe.failureThreshold | int | `2` |  |
| web.readinessProbe.httpGet.endpoint | string | `"/api/hc?source=readinessProbe"` |  |
| web.readinessProbe.httpGet.httpHeaders | list | `[]` |  |
| web.readinessProbe.initialDelaySeconds | int | `0` |  |
| web.readinessProbe.periodSeconds | int | `10` |  |
| web.readinessProbe.successThreshold | int | `1` |  |
| web.readinessProbe.timeoutSeconds | int | `5` |  |
| web.replicaCount | int | `1` |  |
| web.resources | object | `{}` |  |
| web.runtimeClassName | string | `nil` |  |
| web.service.annotations | object | `{}` |  |
| web.service.enabled | bool | `true` |  |
| web.service.port | int | `3000` |  |
| web.service.type | string | `"ClusterIP"` |  |
| web.terminationGracePeriodSeconds | int | `0` |  |
| web.tolerations | list | `[]` |  |
| web.updateStrategy.rollingUpdate.maxSurge | int | `1` |  |
| web.updateStrategy.rollingUpdate.maxUnavailable | int | `0` |  |
| web.updateStrategy.type | string | `"RollingUpdate"` |  |

You should specify additional `AIRBROKE_` environment variables using the `extraEnvs` parameter.

### Pgbouncer

Pgbouncer, a lightweight connection pooler for PostgreSQL, can be enabled using the `pgbouncer.enabled` parameter. You can customize the Pgbouncer configuration under `pgbouncer.config`.

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
```

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: airbroke
  namespace: airbroke
spec:
  releaseName: airbroke
  chart:
    spec:
      chart: airbroke
      version: ">= 1.2.4"
      sourceRef:
        kind: HelmRepository
        name: icoretech
        namespace: flux-system
  interval: 10m0s
  install:
    remediation:
      retries: 4
  upgrade:
    remediation:
      retries: 4
  values:
    database:
      url: 'postgresql://xxxx:xxxx@pgbouncer.default.svc.cluster.local:5432/airbroke_production?connection_limit=100&pool_timeout=10&application_name=airbroke&schema=public'
      migrations_url: 'postgresql://xxxx:xxxx@postgres-postgresql.postgres.svc.cluster.local:5432/airbroke_production?schema=public'
    web:
      image: ghcr.io/icoretech/airbroke:1.1.81 # {"$imagepolicy": "flux-system:airbroke"}
      replicaCount: 2
      cachePersistentVolume:
        enabled: true
        storageClass: efs
        accessModes:
          - ReadWriteMany
        size: 1Gi
      hpa:
        enabled: true
        maxReplicas: 5
        cpu: 100
      resources:
        requests:
          cpu: 1500m
          memory: 500M
        limits:
          cpu: 1500m
          memory: 500M
      extraEnvs:
        - name: AIRBROKE_GITHUB_ID
          value: "xxxx"
        - name: AIRBROKE_GITHUB_SECRET
          value: "xxxxx"
        - name: AIRBROKE_GITHUB_ORGS
          value: "xxxxx"
        - name: NEXTAUTH_SECRET
          value: "xxxxxxx"
        - name: NEXTAUTH_URL
          value: "https://xxxxxx"
        - name: AIRBROKE_OPENAI_API_KEY
          value: "sk-xxxxxxx"
      ingress:
        enabled: true
        ingressClassName: nginx
        annotations:
          cert-manager.io/cluster-issuer: letsencrypt
          external-dns.alpha.kubernetes.io/cloudflare-proxied: 'false'
          nginx.ingress.kubernetes.io/configuration-snippet: |
            real_ip_header proxy_protocol;
        hosts:
          - host: airbroke.mydomain.com
            paths:
              - '/'
        tls:
          - hosts:
              - airbroke.mydomain.com
```

Please be aware that the previous example serves as a basic template, and you'll likely need to adjust it to suit your specific requirements. For a comprehensive list of configurable options, please consult the values.yaml file. It's important to note that the image value included above is just a placeholder, and you should substitute it with your desired [image tag](https://github.com/icoretech/airbroke/pkgs/container/airbroke).

For automated image updates, consider utilizing [Flux Image Automation](https://fluxcd.io/docs/guides/image-update/).
Our images are deliberately tagged to facilitate Flux's automatic deployment updates whenever a new image becomes available.

## Image Policies

```yaml
# example production semver image policy
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: airbroke
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: airbroke
  policy:
    semver:
      range: '>=1.1.22 <2.0.0'
```

```yaml
# example development image policy
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: airbroke
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: airbroke
  filterTags:
    pattern: '^main-[a-fA-F0-9]+-(?P<ts>.*)'
    extract: '$ts'
  policy:
    numerical:
      order: asc
```
