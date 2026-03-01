---
layout: default
title: browserless
---

# Browserless Helm Chart

Deploy [Browserless](https://www.browserless.io/) on Kubernetes with Browserless v2 defaults, token authentication enforcement, and image presets for multiple browsers.

## Features

- Browserless v2-focused defaults (`CONCURRENT`, `QUEUED`, `TIMEOUT`, etc.)
- Token authentication required (`config.token`, `config.tokenSecretRef`, or `extraEnv` with `TOKEN`)
- Multi-browser image presets via `image.browser` (`chromium`, `chrome`, `firefox`, `multi`)
- Optional image repository override for custom/private registries
- Configurable readiness/liveness probes, HPA, service type, and scheduling knobs

## Prerequisites

- Kubernetes 1.24+
- Helm 3.10+

## Install

```bash
helm repo add icoretech https://icoretech.github.io/helm
helm repo update
helm upgrade --install browserless icoretech/browserless \
  -n browserless --create-namespace \
  --set config.token="replace-me"
```

OCI:

```bash
helm upgrade --install browserless oci://ghcr.io/icoretech/charts/browserless \
  -n browserless --create-namespace \
  --set config.token="replace-me"
```

## Token via Secret (recommended)

```yaml
config:
  token: null
  tokenSecretRef:
    name: browserless-auth
    key: token
```

## Browser presets

```yaml
image:
  browser: firefox
  # repository: ghcr.io/browserless/firefox # optional explicit override
  # tag: v2.42.0                           # optional override
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
  name: browserless
  namespace: browserless
spec:
  interval: 5m
  chart:
    spec:
      chart: browserless
      version: ">=0.1.1"
      sourceRef:
        kind: HelmRepository
        name: icoretech
        namespace: flux-system
  values:
    image:
      browser: chromium
    config:
      tokenSecretRef:
        name: browserless-auth
        key: token
```

## Configuration reference

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity. |
| autoscaling.enabled | bool | `false` | Enable HPA. |
| autoscaling.maxReplicas | int | `20` | Maximum replicas. |
| autoscaling.minReplicas | int | `1` | Minimum replicas. |
| autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage. |
| autoscaling.targetMemoryUtilizationPercentage | string | `nil` | Target memory utilization percentage. |
| config | object | `{"allowFileProtocol":null,"allowGet":null,"concurrent":4,"corsAllowMethods":null,"corsAllowOrigin":null,"corsMaxAge":null,"dataDir":null,"debug":"-*","downloadDir":null,"enableCors":null,"errorAlertUrl":null,"external":null,"host":"0.0.0.0","maxCpuPercent":null,"maxMemoryPercent":null,"metricsJsonPath":null,"port":3000,"queued":10,"timeout":600000,"token":"change-me","tokenSecretRef":null}` | Browserless configuration mapped to environment variables. |
| config.allowFileProtocol | string | `nil` | Allow file:// protocol. |
| config.allowGet | string | `nil` | Allow GET requests. |
| config.concurrent | int | `4` | Max concurrent sessions. |
| config.corsAllowMethods | string | `nil` | CORS allowed methods. |
| config.corsAllowOrigin | string | `nil` | CORS allowed origins. |
| config.corsMaxAge | string | `nil` | CORS max age (seconds). |
| config.dataDir | string | `nil` | Data directory path. |
| config.debug | string | `"-*"` | Debug selector (e.g. "-*" to reduce logs). |
| config.downloadDir | string | `nil` | Download directory path. |
| config.enableCors | string | `nil` | Enable CORS. |
| config.errorAlertUrl | string | `nil` | Callback URL for Browserless runtime errors. |
| config.external | string | `nil` | Example: https://browserless.example.com |
| config.host | string | `"0.0.0.0"` | Bind host. |
| config.maxCpuPercent | string | `nil` | Overload protection CPU threshold percentage. |
| config.maxMemoryPercent | string | `nil` | Overload protection memory threshold percentage. |
| config.metricsJsonPath | string | `nil` | Metrics JSON path. |
| config.port | int | `3000` | Bind port. |
| config.queued | int | `10` | Max queued sessions. |
| config.timeout | int | `600000` | Max session timeout in milliseconds. |
| config.token | string | `"change-me"` | Change this in production. |
| config.tokenSecretRef | string | `nil` | key: token |
| envFrom | list | `[]` | Extra envFrom entries. |
| extraEnv | list | `[]` | Additional environment variables. |
| fullnameOverride | string | `""` | Override fully-qualified release name. |
| image.browser | string | `"chromium"` | Supported presets: chromium, chrome, firefox, multi. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.repository | string | `""` | Image repository override. When empty, defaults to ghcr.io/browserless/<browser>. |
| image.tag | string | `""` | Image tag override. Defaults to Chart appVersion. |
| imagePullSecrets | list | `[]` | List of image pull secrets. |
| livenessProbe | object | `{"failureThreshold":3,"initialDelaySeconds":5,"periodSeconds":10,"successThreshold":1,"tcpSocket":{"port":"http"},"timeoutSeconds":1}` | Liveness probe. |
| nameOverride | string | `""` | Override chart name. |
| nodeSelector | object | `{}` | Node selector. |
| podAnnotations | object | `{}` | Pod annotations. |
| podLabels | object | `{}` | Pod labels. |
| podSecurityContext | object | `{}` | Pod security context. |
| readinessProbe | object | `{"exec":{"command":["/bin/sh","-ec","wget -qO- \"http://127.0.0.1:${PORT:-3000}/pressure?token=${TOKEN}\" >/dev/null"]},"failureThreshold":3,"initialDelaySeconds":5,"periodSeconds":10,"successThreshold":1,"timeoutSeconds":1}` | Readiness probe. |
| replicaCount | int | `1` | Number of replicas. |
| resources | object | `{}` | Container resources. |
| securityContext | object | `{}` | Container security context. |
| service.annotations | object | `{}` | Service annotations. |
| service.externalTrafficPolicy | string | `nil` | External traffic policy. |
| service.loadBalancerIP | string | `nil` | Optional LoadBalancer IP. |
| service.loadBalancerSourceRanges | list | `[]` | Optional CIDRs allowed via LoadBalancer. |
| service.nodePort | string | `nil` | Optional nodePort. |
| service.port | int | `80` | Service port. |
| service.type | string | `"ClusterIP"` | Service type. |
| serviceAccount.annotations | object | `{}` | Service account annotations. |
| serviceAccount.create | bool | `true` | Create a service account. |
| serviceAccount.name | string | `""` | Service account name. |
| tolerations | list | `[]` | Tolerations. |
| volumeMounts | list | `[]` | Additional volume mounts. |
| volumes | list | `[]` | Additional volumes. |
