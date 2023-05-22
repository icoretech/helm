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

```bash
# OCI
helm install my-airbroke oci://ghcr.io/icoretech/charts/airbroke
```

```bash
helm repo add icoretech https://icoretech.github.io/helm
helm install my-airbroke icoretech/airbroke
```

Please remember to set at least the `database.url` and `database.migrations_url` values. Continue reading for further details.

## Database

The `database.url` and `database.migrations_url` values must be set to the connection string of your PostgreSQL database.

## Configuration

The following table lists the configurable parameters of the Airbroke chart and their default values.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `nameOverride` | String to partially override airbroke.fullname | `""` |
| `fullnameOverride` | String to fully override airbroke.fullname | `""` |
| `database.url` | PostgreSQL connection string | `""` |
| `database.migrations_url` | PostgreSQL connection string for migrations | `""` |
| `web.image` | Docker image for the web application | `ghcr.io/icoretech/airbroke:1.1.11` |
| `web.replicaCount` | Number of replicas to run | `1` |
| `web.updateStrategy` | Update strategy to use | `{type: RollingUpdate, rollingUpdate: {maxUnavailable: 0, maxSurge: 1}}` |
| `web.hpa.enabled` | Enables the Horizontal Pod Autoscaler | `false` |
| `web.ingress.enabled` | Enables Ingress | `false` |
| `pgbouncer.enabled` | Enables Pgbouncer, a lightweight connection pooler for PostgreSQL | `false` |

Please note, this is a simplified version of the parameters for the purpose of this README. For full configuration options, please refer to the `values.yaml` file.

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
      version: ">= 1.1.3"
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
      url: 'postgresql://xxxx:xxxx@pgbouncer.default.svc.cluster.local:5432/airbroke_production?pgbouncer=true&connection_limit=100&pool_timeout=10&application_name=airbroke&schema=public'
      migrations_url: 'postgresql://xxxx:xxxx@postgres-postgresql.postgres.svc.cluster.local:5432/airbroke_production?schema=public'
    web:
      image: ghcr.io/icoretech/airbroke:main-c5d425f-1683936478 # {"$imagepolicy": "flux-system:airbroke"}
      replicaCount: 2
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
        - name: AIRBROKE_NEXTAUTH_SECRET
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
      range: '>=1.1.3 <2.0.0'
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
