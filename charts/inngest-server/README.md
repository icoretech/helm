# Inngest Server Helm Chart

This Helm chart deploys [Inngest](https://www.inngest.com/docs/self-hosting) Server.

## Installing the Chart

To install the chart with the release name `my-inngest-server`:

```console
# OCI
helm install my-inngest-server oci://ghcr.io/icoretech/charts/inngest-server
```

```console
helm repo add icoretech https://icoretech.github.io/helm
helm install my-inngest-server icoretech/inngest-server
```

## Configuration

The following table lists the configurable parameters of the inngest-server chart and their default values.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity settings for pod assignment |
| autoscaling.enabled | bool | `false` | Enable Horizontal POD autoscaling |
| autoscaling.maxReplicas | int | `100` | Maximum number of replicas |
| autoscaling.minReplicas | int | `1` | Minimum number of replicas |
| autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage |
| autoscaling.targetMemoryUtilizationPercentage | int | `80` | Target Memory utilization percentage |
| config.eventKey | string | `""` | Event key that the server uses for ingesting events. In production, you can generate a random key with: `openssl rand -hex 16` This key must be the same in your code that sends events to Inngest. |
| config.logLevel | string | `"info"` |  |
| config.redisUri | string | `""` | If you want the server to use an external Redis, you can specify that here, otherwise leave empty string |
| config.signingKey | string | `""` | Signing key for authenticating traffic between Inngest and your app. |
| extraEnv | list | `[]` | Additional environment variables to be added to the pods. |
| fullnameOverride | string | `""` | String to fully override `"inngest.fullname"` |
| image.pullPolicy | string | `"Always"` | image pull policy |
| image.repository | string | `"inngest/inngest"` | image repository |
| image.tag | string | `"v1.5.12"` | Overrides the image tag |
| imagePullSecrets | list | `[]` | If defined, uses a Secret to pull an image from a private Docker registry or repository. imagePullSecrets:   - name: regcred |
| ingress.annotations | object | `{}` | Additional annotations for the Ingress resource |
| ingress.className | string | `""` | IngressClass that will be be used to implement the Ingress |
| ingress.enabled | bool | `false` | Enable ingress record generation |
| ingress.hosts | list | see [values.yaml](./values.yaml) | An array with hosts and paths |
| ingress.tls | list | `[]` | An array with the tls configuration |
| nameOverride | string | `""` | Provide a name in place of `inngest` |
| nodeSelector | object | `{}` | Node labels for pod assignment |
| persistence.accessModes | list | `["ReadWriteOnce"]` | AccessModes define the way the volume can be accessed by the pods. Common modes:   - ReadWriteOnce  (RWO)   - ReadWriteMany  (RWX)   - ReadOnlyMany   (ROX) Typically, ReadWriteOnce is enough for a single-node usage or simple setups. |
| persistence.annotations | object | `{}` | Annotations to apply to the PVC itself. Useful for specifying extra metadata, monitoring tags, or dynamic provisioning parameters. |
| persistence.enabled | bool | `false` | Whether to enable persistent storage for the Inngest server's data. If enabled, a PersistentVolumeClaim (PVC) will be created and mounted as /data in the container (or wherever the volumeMount is set). |
| persistence.size | string | `"1Gi"` | The size of the persistent volume requested, e.g. "1Gi", "5Gi", "10Gi". |
| persistence.storageClass | string | `"-"` | Name of a valid StorageClass on your cluster (e.g. "standard", "gp2"). If set to "-", Helm will generate a PVC without specifying a storageClassName (useful if you rely on a default StorageClass). If set to a valid StorageClass, that class is used explicitly. Example: "standard", "gp2", "my-custom-class" |
| persistence.volumeMode | string | `""` | volumeMode defines how Kubernetes presents the underlying volume to a pod If empty, it defaults to "Filesystem" (depending on the StorageClass/driver and K8s version). |
| podAnnotations | object | `{}` | Annotations to be added to the pods |
| podSecurityContext | object | `{}` | pod-level security context |
| replicaCount | int | `1` | Number of replicas |
| resources | object | `{}` | Resource limits and requests for the controller pods. |
| revisionHistoryLimit | int | `10` | The number of old ReplicaSets to retain |
| securityContext | object | `{}` | container-level security context |
| service.port | int | `8288` | Kubernetes port where service is exposed |
| service.type | string | `"ClusterIP"` | Kubernetes service type |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.create | bool | `true` | Specifies whether a service account should be created |
| serviceAccount.name | string | `""` | The name of the service account to use. If not set and create is true, a name is generated using the fullname template |
| tolerations | list | `[]` | Toleration labels for pod assignment |

## Example using Flux

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: icoretech
  namespace: flux-system
spec:
  interval: 30m
  type: oci
  url: oci://ghcr.io/icoretech/charts
```

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: inngest-server
  namespace: inngest
spec:
  releaseName: inngest-server
  chart:
    spec:
      chart: inngest-server
      version: ">= 1.0.0"
      sourceRef:
        kind: HelmRepository
        name: icoretech
        namespace: flux-system
  values:
    image:
      tag: "v1.3.3" # {"$imagepolicy": "flux-system:inngest:tag"}
    config:
      eventKey: d004fd315b7668191cfdd08468639992
      signingKey: d06137e83fe64fb868f85932a98f6d1a
    persistence:
      enabled: true
```

For automated image updates, consider utilizing [Flux Image Automation](https://fluxcd.io/docs/guides/image-update/).

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: inngest
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: inngest
  filterTags:
    pattern: '^v(?P<semver>[0-9]+\.[0-9]+\.[0-9]+)$'
    extract: '$semver'
  policy:
    semver:
      range: '>=1.3.3'
```
