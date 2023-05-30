# ChatGPT Retrieval Plugin Helm Chart

This Helm chart deploys the [ChatGPT Retrieval Plugin](https://github.com/openai/chatgpt-retrieval-plugin).

## Prerequisites

- [Supported Vector Database of your choice](https://github.com/icoretech/chatgpt-retrieval-plugin-docker#supported-vector-database-providers)
- Helm 3.10+

## Installing the Chart

To install the chart with the release name `mychatgpt`:

```bash
# OCI
helm install mychatgpt oci://ghcr.io/icoretech/charts/chatgpt-retrieval-plugin
```

```bash
helm repo add icoretech https://icoretech.github.io/helm
helm install mychatgpt icoretech/chatgpt-retrieval-plugin
```

## Note about Docker Image

Please ensure that you select the correct Docker image flavor based on the supported vector database provider you intend to use. Refer to the [Supported Vector Database Providers](https://github.com/icoretech/chatgpt-retrieval-plugin-docker#supported-vector-database-providers) for more information.

## Configuration

You must set the values for `web.extraEnvs`.

The following table lists the configurable parameters of the ChatGPT Retrieval Plugin chart and their default values.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `nameOverride` | String to partially override the chart's fullname | `""` |
| `fullnameOverride` | String to fully override the chart's fullname | `""` |
| `web.image` | Docker image for the web application | `ghcr.io/icoretech/chatgpt-retrieval-plugin-docker:redis-9969191-1685433326` |
| `web.replicaCount` | Number of replicas to run | `1` |
| `web.updateStrategy` | Update strategy to use | `RollingUpdate` |
| `web.hpa.enabled` | Enables the Horizontal Pod Autoscaler | `false` |
| `web.ingress.enabled` | Enables Ingress | `false` |
| `web.service.enabled` | Enables the Kubernetes service | `true` |
| `web.service.type` | Kubernetes service type | `ClusterIP` |
| `web.service.port` | Port for the Kubernetes service | `8080` |
| `web.livenessProbe.enabled` | Enables the liveness probe | `false` |
| `web.readinessProbe.enabled` | Enables the readiness probe | `false` |
| `web.resources` | Resource limits and requests for the web application | `{}` |
| `web.extraEnvs` | Additional environment variables for the web application | `[]` |

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
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: chatgpt-retrieval-plugin-docker
  namespace: flux-system
spec:
  image: ghcr.io/icoretech/chatgpt-retrieval-plugin-docker
  interval: 1h0m0s
```

```yaml
# redis flavour
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: chatgpt-retrieval-plugin-redis
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: chatgpt-retrieval-plugin-docker
  filterTags:
    pattern: '^redis-[a-fA-F0-9]+-(?P<ts>.*)'
    extract: '$ts'
  policy:
    numerical:
      order: asc
```

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: chatgpt-retrieval-plugin
  namespace: chatgpt-retrieval-plugin
spec:
  releaseName: chatgpt-retrieval-plugin
  chart:
    spec:
      chart: chatgpt-retrieval-plugin
      version: ">= 0.0.1"
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
    web:
      image: ghcr.io/icoretech/chatgpt-retrieval-plugin-docker:redis-9969191-1685433326 # {"$imagepolicy": "flux-system:chatgpt-retrieval-plugin-redis"}
      replicaCount: 1
      hpa:
        enabled: true
        maxReplicas: 5
        cpu: 100
      resources:
        requests:
          cpu: 1500m # example values
          memory: 500M # example values
        limits:
          cpu: 1500m # example values
          memory: 500M # example values
      extraEnvs:
        - name: DATASTORE
          value: "xxxx"
        - name: BEARER_TOKEN
          value: "xxxxx"
        - name: OPENAI_API_KEY
          value: "xxxxx"
        # and more https://github.com/openai/chatgpt-retrieval-plugin/tree/main#quickstart
      ingress:
        enabled: true
        ingressClassName: nginx
        annotations:
          cert-manager.io/cluster-issuer: letsencrypt
          external-dns.alpha.kubernetes.io/cloudflare-proxied: 'false'
          nginx.ingress.kubernetes.io/configuration-snippet: |
            real_ip_header proxy_protocol;
        hosts:
          - host: mychatgpt.mydomain.com
            paths:
              - '/'
        tls:
          - hosts:
              - mychatgpt.mydomain.com
```
