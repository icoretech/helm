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

Please ensure that you select the correct Docker image flavor based on the supported vector database provider you intend to use. Refer to the [Supported Vector Database Providers](https://github.com/icoretech/chatgpt-retrieval-plugin-docker#-supported-vector-database-providers) for more information.

## Endpoints to test

- <https://youringress/openapi.json>
- <https://youringress/docs>

## Configuration

You must set the values for `web.extraEnvs`.

The following table lists the configurable parameters of the ChatGPT Retrieval Plugin chart and their default values.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `nameOverride` | Overrides part of the chart's fullname. Useful when integrating with other charts. | `""` |
| `fullnameOverride` | Completely overrides the chart's fullname. Useful for custom naming conventions. | `""` |
| `web.image` | Docker image for the plugin, including the tag. | `ghcr.io/icoretech/chatgpt-retrieval-plugin-docker:postgres-9969191-1685433326` |
| `web.imagePullPolicy` | Policy for pulling images: `Always`, `IfNotPresent`, `Never`. | `IfNotPresent` |
| `web.imagePullSecrets` | Secrets for pulling images from private registries. Must exist in namespace. Format as string name of the secret. | `""` |
| `web.replicaCount` | Number of pod replicas for the deployment. | `1` |
| `web.updateStrategy` | Strategy for updating pods. Supports `RollingUpdate` (default) or `Recreate`. | `RollingUpdate` |
| `web.hpa.enabled` | Enables horizontal pod autoscaling based on CPU/memory usage or HTTP requests. | `false` |
| `web.ingress.enabled` | Enables ingress for external access. Configure `hosts` and `tls` as needed. | `false` |
| `web.service.enabled` | Enables a Kubernetes service for internal networking. | `true` |
| `web.service.type` | Type of the Kubernetes service, e.g., `ClusterIP`, `NodePort`, `LoadBalancer`. | `ClusterIP` |
| `web.service.port` | Port exposed by the service. | `8080` |
| `web.livenessProbe.enabled` | Enables a liveness probe. Currently not available (`false`). | `false` |
| `web.readinessProbe.enabled` | Enables a readiness probe. Currently not available (`false`). | `false` |
| `web.resources` | CPU/memory resources allocation. Use for limits and requests. | `{}` |
| `web.nodeSelector` | Node labels for pod assignment. Helps ensure pods are deployed on specified nodes. | `{}` |
| `web.tolerations` | Tolerations for pod assignment. Allows scheduling on tainted nodes. | `[]` |
| `web.affinity` | Affinity and anti-affinity rules. Controls pod scheduling preferences. | `{}` |
| `web.extraEnvs` | Additional environment variables for customization. Useful for setting up external integrations. | `[]` |
| `web.extraEnvFromSecret` | Sources environment variables from a Kubernetes secret. Useful for sensitive configs. Format as list of secret names. | `[]` |
| `web.config.aiPluginJson` | Configuration for the AI plugin in JSON format. Defines plugin metadata and API details. | `""` |
| `web.config.openApiYaml` | OpenAPI spec for the plugin's API. Defines endpoints and operations. | `""` |

To customize the configuration, you can provide your own values by creating a `values.yaml` file and overriding the desired parameters.

Here's an example `values.yaml` file with the `web.config` options:

```yaml
web:
  config:
    aiPluginJson:
      schema_version: "v1"
      name_for_model: "retrieval"
      name_for_human: "Retrieval Plugin"
      description_for_model: "Plugin for searching through the user's documents (such as files, emails, and more) to find answers to questions and retrieve relevant information. Use it whenever a user asks something that might be found in their personal information."
      description_for_human: "Search through your documents."
      auth:
        type: "none"
      api:
        type: "openapi"
        url: "https://mychatgpt.zyx/.well-known/openapi.yaml"
      logo_url: "https://mychatgpt.zyx/.well-known/logo.png"
      contact_email: "hello@mychatgpt.zyx"
      legal_info_url: "https://mychatgpt.zyx/legal"

    openApiYaml: |
      openapi: 3.0.2
      info:
        title: Retrieval Plugin API
        description: A retrieval API for querying and filtering documents based on natural language queries and metadata
        version: 1.0.0
      servers:
        - url: https://your-app-url.com
      ...

```

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
# weaviate flavour
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: chatgpt-retrieval-plugin-weaviate
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: chatgpt-retrieval-plugin-docker
  filterTags:
    pattern: '^weaviate-[a-fA-F0-9]+-(?P<ts>.*)'
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
      version: ">= 0.0.8"
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
      image: ghcr.io/icoretech/chatgpt-retrieval-plugin-docker:weaviate-9969191-1685462163 # {"$imagepolicy": "flux-system:chatgpt-retrieval-plugin-weaviate"}
      replicaCount: 1
      config:
        aiPluginJson:
          schema_version: "v1"
          name_for_model: "retrieval"
          name_for_human: "Retrieval Plugin"
          description_for_model: "Plugin for searching through the user's documents (such as files, emails, and more) to find answers to questions and retrieve relevant information. Use it whenever a user asks something that might be found in their personal information."
          description_for_human: "Search through your documents."
          auth:
            type: "none"
          api:
            type: "openapi"
            url: "https://mygpt.xxxx.ch/.well-known/openapi.yaml"
          logo_url: "https://mygpt.xxxx.ch/.well-known/logo.png"
          contact_email: "mygpt@xxxx.ch"
          legal_info_url: "https://mygpt.xxxx.ch/legal"
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
        - name: WEAVIATE_URL
          value: http://weaviate:80
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
