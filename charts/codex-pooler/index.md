---
layout: default
title: codex-pooler
---

# Codex Pooler Helm Chart

Deploy [Codex Pooler](https://github.com/icoretech/codex-pooler), a self-hosted gateway for sharing Codex account capacity across trusted agents and tools, on Kubernetes.

## Prerequisites

- Kubernetes 1.24+
- Helm 3.10+
- PostgreSQL database reachable from the cluster
- Existing Kubernetes Secret with the release bootstrap values, unless `secrets.create=true` is used from a private values source

## Install

```bash
helm repo add icoretech https://icoretech.github.io/helm
helm repo update
helm upgrade --install codex-pooler icoretech/codex-pooler \
  -n codex-pooler --create-namespace \
  --version 0.1.3 \
  --values values.production.yaml
```

OCI:

```bash
helm upgrade --install codex-pooler oci://ghcr.io/icoretech/charts/codex-pooler \
  -n codex-pooler --create-namespace \
  --version 0.1.3 \
  --values values.production.yaml
```

## Image

The application image is published at `ghcr.io/icoretech/codex-pooler`. When `image.tag` is empty, the chart uses `appVersion`.

```yaml
image:
  repository: ghcr.io/icoretech/codex-pooler
  tag: 0.1.1
  pullPolicy: IfNotPresent
```

## Required Secret

By default, the chart expects an existing Secret named `codex-pooler-secrets`:

```yaml
secrets:
  create: false
  existingSecret: codex-pooler-secrets
```

The Secret must contain these keys:

- `database-url`
- `secret-key-base`
- `totp-encryption-key`
- `totp-key-version`
- `upstream-secret-key`
- `upstream-secret-key-version`

Do not put upstream access tokens, API keys, cookies, `auth.json`, SMTP passwords, or raw client payloads in chart values.

## Roles

- `app` serves HTTP with `OBAN_MODE=web` and `PHX_SERVER=true`
- `oban.worker` runs background jobs with `OBAN_MODE=worker`
- `oban.scheduler` runs scheduled jobs with `OBAN_MODE=scheduler`
- `migrations` runs release migrations and imports the vendored pricing feed before app rollout

Keep `app.replicaCount` at `1` unless clustering and owner-forwarding are intentionally configured and verified.

## Monitoring

The app service can render a Prometheus Operator `ServiceMonitor`:

```yaml
monitoring:
  serviceMonitor:
    enabled: true
    labels:
      release: kube-prometheus-stack
    interval: 10s
    scrapeTimeout: 5s
    path: /metrics
```

If metrics bearer authentication is enabled in Codex Pooler, keep the raw token in a Kubernetes Secret and reference it through `monitoring.serviceMonitor.bearerTokenSecret`.

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
  name: codex-pooler
  namespace: codex-pooler
spec:
  interval: 5m
  chart:
    spec:
      chart: codex-pooler
      version: "0.1.3"
      sourceRef:
        kind: HelmRepository
        name: icoretech
        namespace: flux-system
  values:
    image:
      repository: ghcr.io/icoretech/codex-pooler
      tag: "0.1.1"
    config:
      host: codex-pooler.example.com
    ingress:
      enabled: true
      hosts:
        - host: codex-pooler.example.com
          paths:
            - path: /
              pathType: Prefix
    secrets:
      create: false
      existingSecret: codex-pooler-secrets
```

## Configuration Reference

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| app.affinity | object | `{}` |  |
| app.drainMarkerPath | string | `"/tmp/codex-pooler-draining"` |  |
| app.enabled | bool | `true` |  |
| app.lifecycle.preStop.enabled | bool | `true` |  |
| app.lifecycle.preStop.sleepSeconds | int | `10` |  |
| app.nodeSelector | object | `{}` |  |
| app.podAnnotations | object | `{}` |  |
| app.podDisruptionBudget.enabled | bool | `true` |  |
| app.podDisruptionBudget.minAvailable | int | `1` |  |
| app.replicaCount | int | `1` |  |
| app.resources.limits.cpu | string | `"1000m"` |  |
| app.resources.limits.memory | string | `"768Mi"` |  |
| app.resources.requests.cpu | string | `"100m"` |  |
| app.resources.requests.memory | string | `"512Mi"` |  |
| app.service.port | int | `4000` |  |
| app.service.type | string | `"ClusterIP"` |  |
| app.startupProbe.enabled | bool | `true` |  |
| app.startupProbe.failureThreshold | int | `12` |  |
| app.startupProbe.initialDelaySeconds | int | `5` |  |
| app.startupProbe.path | string | `"/healthz"` |  |
| app.startupProbe.periodSeconds | int | `5` |  |
| app.startupProbe.timeoutSeconds | int | `2` |  |
| app.strategy.maxSurge | int | `1` |  |
| app.strategy.maxUnavailable | int | `0` |  |
| app.terminationGracePeriodSeconds | int | `75` |  |
| app.tolerations | list | `[]` |  |
| app.websocketContinuity.allowUnsafeMultiReplica | bool | `false` |  |
| app.websocketContinuity.ownerForwarding.enabled | bool | `false` |  |
| clustering.cookie.existingSecret | string | `""` |  |
| clustering.cookie.existingSecretKey | string | `"release-cookie"` |  |
| clustering.cookie.value | string | `""` |  |
| clustering.distributionPort | string | `"9000"` |  |
| clustering.enabled | bool | `false` |  |
| clustering.epmdPort | string | `"4369"` |  |
| clustering.headlessService.enabled | bool | `true` |  |
| clustering.headlessService.nameOverride | string | `""` |  |
| clustering.headlessService.publishNotReadyAddresses | bool | `true` |  |
| clustering.participants.app | bool | `true` |  |
| clustering.participants.scheduler | bool | `true` |  |
| clustering.participants.worker | bool | `true` |  |
| clustering.query | string | `""` |  |
| config.ectoIpv6 | string | `"false"` |  |
| config.host | string | `"codex-pooler.example.com"` |  |
| config.lang | string | `"C.UTF-8"` |  |
| config.lcAll | string | `"C.UTF-8"` |  |
| config.obanJobsQueueLimit | string | `"8"` |  |
| config.obanShutdownGracePeriodMs | string | `"55000"` |  |
| config.poolSize | int | `10` |  |
| config.port | int | `4000` |  |
| fullnameOverride | string | `""` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"ghcr.io/icoretech/codex-pooler"` |  |
| image.tag | string | `""` | Image tag. Defaults to the chart appVersion when empty. |
| imagePullSecrets | list | `[]` |  |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `""` |  |
| ingress.enabled | bool | `false` |  |
| ingress.hosts[0].host | string | `"codex-pooler.example.com"` |  |
| ingress.hosts[0].paths[0].path | string | `"/"` |  |
| ingress.hosts[0].paths[0].pathType | string | `"Prefix"` |  |
| ingress.tls | list | `[]` |  |
| migrations.enabled | bool | `true` |  |
| migrations.resources.limits.cpu | string | `"250m"` |  |
| migrations.resources.limits.memory | string | `"384Mi"` |  |
| migrations.resources.requests.cpu | string | `"50m"` |  |
| migrations.resources.requests.memory | string | `"192Mi"` |  |
| migrations.ttlSecondsAfterFinished | int | `300` |  |
| monitoring.serviceMonitor.annotations | object | `{}` |  |
| monitoring.serviceMonitor.bearerTokenSecret.key | string | `""` |  |
| monitoring.serviceMonitor.bearerTokenSecret.name | string | `""` |  |
| monitoring.serviceMonitor.enabled | bool | `false` |  |
| monitoring.serviceMonitor.interval | string | `"30s"` |  |
| monitoring.serviceMonitor.labels | object | `{}` |  |
| monitoring.serviceMonitor.metricRelabelings | list | `[]` |  |
| monitoring.serviceMonitor.path | string | `"/metrics"` |  |
| monitoring.serviceMonitor.relabelings | list | `[]` |  |
| monitoring.serviceMonitor.scheme | string | `"http"` |  |
| monitoring.serviceMonitor.scrapeTimeout | string | `"10s"` |  |
| nameOverride | string | `""` |  |
| oban.scheduler.affinity | object | `{}` |  |
| oban.scheduler.enabled | bool | `true` |  |
| oban.scheduler.nodeSelector | object | `{}` |  |
| oban.scheduler.podAnnotations | object | `{}` |  |
| oban.scheduler.replicaCount | int | `1` |  |
| oban.scheduler.resources.limits.cpu | string | `"500m"` |  |
| oban.scheduler.resources.limits.memory | string | `"584Mi"` |  |
| oban.scheduler.resources.requests.cpu | string | `"75m"` |  |
| oban.scheduler.resources.requests.memory | string | `"584Mi"` |  |
| oban.scheduler.strategy.maxSurge | int | `1` |  |
| oban.scheduler.strategy.maxUnavailable | int | `0` |  |
| oban.scheduler.terminationGracePeriodSeconds | int | `75` |  |
| oban.scheduler.tolerations | list | `[]` |  |
| oban.worker.affinity | object | `{}` |  |
| oban.worker.enabled | bool | `true` |  |
| oban.worker.nodeSelector | object | `{}` |  |
| oban.worker.podAnnotations | object | `{}` |  |
| oban.worker.replicaCount | int | `1` |  |
| oban.worker.resources.limits.cpu | string | `"500m"` |  |
| oban.worker.resources.limits.memory | string | `"768Mi"` |  |
| oban.worker.resources.requests.cpu | string | `"75m"` |  |
| oban.worker.resources.requests.memory | string | `"768Mi"` |  |
| oban.worker.strategy.maxSurge | int | `1` |  |
| oban.worker.strategy.maxUnavailable | int | `0` |  |
| oban.worker.terminationGracePeriodSeconds | int | `75` |  |
| oban.worker.tolerations | list | `[]` |  |
| podAnnotations | object | `{}` |  |
| secrets.create | bool | `false` |  |
| secrets.databaseUrl | string | `""` |  |
| secrets.existingSecret | string | `"codex-pooler-secrets"` |  |
| secrets.secretKeyBase | string | `""` |  |
| secrets.totpEncryptionKey | string | `""` |  |
| secrets.totpKeyVersion | string | `"v1"` |  |
| secrets.upstreamSecretKey | string | `""` |  |
| secrets.upstreamSecretKeyVersion | string | `"v1"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
