# Generic Helm chart for Nextjs apps on Kubernetes

This Helm chart deploys Nextjs apps without dependencies.

## Installing the Chart

To install the chart with the release name `my-nextjsapp`:

```bash
# OCI
helm install my-nextjsapp oci://ghcr.io/icoretech/charts/nextjs --set web.image=yourimage
```

```bash
helm repo add icoretech https://icoretech.github.io/helm
helm install my-nextjsapp icoretech/nextjs
```

## Configuration

The following table lists the configurable parameters of the Airbroke chart and their default values.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `nameOverride` | String to partially override airbroke.fullname | `""` |
| `fullnameOverride` | String to fully override airbroke.fullname | `""` |
| `web.image` | Docker image for the web application | `""` |
| `web.replicaCount` | Number of replicas to run | `1` |
| `web.updateStrategy` | Update strategy to use | `{type: RollingUpdate, rollingUpdate: {maxUnavailable: 0, maxSurge: 1}}` |
| `web.hpa.enabled` | Enables the Horizontal Pod Autoscaler | `false` |
| `web.ingress.enabled` | Enables Ingress | `false` |
| `web.cachePersistentVolume.enabled` | Enables a PersistentVolumeClaim for caching | `false` |
| `web.cachePersistentVolume.storageClass` | The storage class to use for the PVC | `""` |
| `web.cachePersistentVolume.existingClaim` | An existing PVC to use for the cache | `""` |
| `web.cachePersistentVolume.accessModes` | The access modes for the PVC | `["ReadWriteOnce"]` |
| `web.cachePersistentVolume.annotations` | Annotations to add to the PVC | `{}` |
| `web.cachePersistentVolume.size` | The size of the PVC | `1Gi` |
| `web.cachePersistentVolume.volumeMode` | The volume mode for the PVC | `""` |
| `web.cachePersistentVolume.mountPath` | The path to mount the volume in the container | `/app/.next/cache` |
