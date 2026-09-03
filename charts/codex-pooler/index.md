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
  --version 0.7.16 \
  --values values.production.yaml
```

OCI:

```bash
helm upgrade --install codex-pooler oci://ghcr.io/icoretech/charts/codex-pooler \
  -n codex-pooler --create-namespace \
  --version 0.7.16 \
  --values values.production.yaml
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

Keep `app.replicaCount` at `1` unless app clustering is intentionally configured and verified. When `app.replicaCount` is `>= 2`, the chart requires app clustering and automatically enables websocket owner forwarding on app pods.

## Rolling Updates And Browser Affinity

Codex Pooler keeps its compiled browser assets inside the release image. No shared object storage or external asset synchronization is required.

With multiple app replicas, a rolling update temporarily serves both the old and new release. Phoenix uses revision-specific digested CSS and JavaScript paths, so a browser can receive HTML from one revision and then request its asset from a pod running the other revision. Ingress controllers that balance every HTTP request independently can return a transient asset `404` in that mixed-revision window.

The chart remains ingress-controller neutral:

- `app.service.annotations` passes arbitrary annotations to the app Service
- `ingress.annotations` passes arbitrary annotations to the Ingress
- `app.service.sessionAffinity` and `app.service.sessionAffinityConfig` expose the standard Kubernetes Service affinity fields

Configure browser cookie affinity using the annotations supported by your ingress controller. For example, Traefik reads its cookie-affinity configuration from the backend Service:

```yaml
app:
  service:
    annotations:
      traefik.ingress.kubernetes.io/service.sticky.cookie: "true"
      traefik.ingress.kubernetes.io/service.sticky.cookie.name: codex-pooler-affinity
      traefik.ingress.kubernetes.io/service.sticky.cookie.secure: "true"
      traefik.ingress.kubernetes.io/service.sticky.cookie.httponly: "true"
      traefik.ingress.kubernetes.io/service.sticky.cookie.samesite: lax
```

Other controllers may require affinity annotations on the Ingress instead; use `ingress.annotations` for those integrations. Kubernetes `sessionAffinity: ClientIP` can help clients that connect directly to the Service, but it is not equivalent to per-browser cookie affinity when an ingress proxy is the Service client:

```yaml
app:
  service:
    sessionAffinity: ClientIP
    sessionAffinityConfig:
      clientIP:
        timeoutSeconds: 300
```

Do not shorten `app.minReadySeconds`, the websocket drain timeout, or the termination grace period to hide asset skew. Those settings protect in-flight websocket turns and spread reconnect load across the rollout; configure affinity at the HTTP routing layer instead.

### Websocket Rollout Drain

The app Deployment keeps `app.minReadySeconds: 120` by default. That delay spaces pod replacement so clients do not all reconnect at once; it is separate from the drain that starts when Kubernetes begins terminating an old pod.

At termination, the app first closes admission for new upstream dispatches, then shares the configured 85-second drain budget across every websocket activity still owned by that pod:

- local websocket owners
- direct websocket turns being handled by the pod
- proxy turns whose websocket is on the pod while their owner runs on another app pod

The drain waits for these activities together, not one class after another. A turn that finishes naturally within the budget is allowed to complete. A turn still active at the deadline is finalized as `owner_drained`; clients should use their normal reconnect or retry path. New work that reaches the pod after the cutoff is rejected before upstream dispatch.

This guarantee is Kubernetes- and ingress-controller-neutral: it does not depend on a particular ingress annotation, shared asset store, or external rollout controller. It takes effect only after the rollout that introduces this behavior has replaced all older app pods, because a terminating pod running an earlier release cannot apply the new admission and drain protocol.

Browser affinity prevents cross-revision HTML and asset requests from bouncing between pods. It does not extend the websocket drain budget.

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
      version: "0.7.16"
      sourceRef:
        kind: HelmRepository
        name: icoretech
        namespace: flux-system
  values:
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
| app.lifecycle.preStop.drainTimeoutSeconds | int | `85` | Maximum seconds to wait for the websocket rollout drain RPC before continuing pod shutdown. The drain returns as soon as in-flight turns finish, so the budget is only consumed while a long turn is actually running; the default is sized so the effective wait (about 10 seconds under the budget) covers p99 in-flight turn durations instead of cutting at p95. |
| app.lifecycle.preStop.enabled | bool | `true` |  |
| app.lifecycle.preStop.sleepSeconds | int | `10` | Seconds to keep the pod unready after the drain marker/RPC before Kubernetes sends SIGTERM. |
| app.minReadySeconds | int | `120` | Seconds a newly ready app pod must stay ready before the rollout continues. Spacing the per-pod websocket drains keeps reconnecting clients from re-uploading their sessions all at once after a deploy; set 0 to disable the pause. |
| app.nodeSelector | object | `{}` |  |
| app.podAnnotations | object | `{}` |  |
| app.podDisruptionBudget.enabled | bool | `true` |  |
| app.podDisruptionBudget.minAvailable | int | `1` |  |
| app.replicaCount | int | `1` |  |
| app.resources.limits | object | `{"memory":"2Gi"}` | No CPU limit by default: the BEAM gateway must burst during post-rollout reconnect storms (TLS + replay body decompression), and CFS throttling there surfaces as client-visible 408 body-read timeouts. Set a limit explicitly only if your platform requires one. |
| app.resources.limits.memory | string | `"2Gi"` | Memory ceiling for the HTTP and long-lived WebSocket gateway process. |
| app.resources.requests.cpu | string | `"100m"` |  |
| app.resources.requests.memory | string | `"512Mi"` |  |
| app.service.annotations | object | `{}` | Arbitrary annotations for the app Service. Use the annotations supported by your ingress or load-balancer controller when browser-level cookie affinity is required during mixed-revision rolling updates. |
| app.service.port | int | `4000` |  |
| app.service.sessionAffinity | string | `"None"` | Kubernetes Service session affinity. ClientIP is useful for clients that reach the Service directly, but it is not a portable replacement for browser cookie affinity behind an ingress controller. |
| app.service.sessionAffinityConfig | object | `{}` | Additional Kubernetes Service session-affinity settings. Set clientIP.timeoutSeconds only when sessionAffinity is ClientIP. |
| app.service.type | string | `"ClusterIP"` |  |
| app.startupProbe.enabled | bool | `true` |  |
| app.startupProbe.failureThreshold | int | `12` |  |
| app.startupProbe.initialDelaySeconds | int | `5` |  |
| app.startupProbe.path | string | `"/healthz"` |  |
| app.startupProbe.periodSeconds | int | `5` |  |
| app.startupProbe.timeoutSeconds | int | `2` |  |
| app.strategy.maxSurge | int | `1` |  |
| app.strategy.maxUnavailable | int | `0` |  |
| app.terminationGracePeriodSeconds | int | `120` | Total shutdown budget. Formula: max(drainTimeoutSeconds + 2 seconds RPC allowance + sleepSeconds, 2 seconds RPC allowance + sleepSeconds + drainTimeoutSeconds for the full in-VM fallback) + 10 seconds endpoint shutdown + 5 seconds margin. |
| app.tolerations | list | `[]` |  |
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
| config.erlMaxPorts | string | `"1048576"` | Bound ERTS port-table capacity independently of a container's file-descriptor rlimit. |
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
