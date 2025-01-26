# Generic Helm chart for Nextjs apps on Kubernetes

This Helm chart deploys Nextjs apps without dependencies.

## Installing the Chart

To install the chart with the release name `my-nextjsapp`:

```bash
# OCI
helm install my-nextjsapp oci://ghcr.io/icoretech/charts/nextjs \
  --set web.image=yourusername/yourimage:tag \
  --set web.extraEnvs[0].name=MYVAR1,web.extraEnvs[0].value=value1 \
  --set web.extraEnvs[1].name=MYVAR2,web.extraEnvs[1].value=value2

```

```bash
helm repo add icoretech https://icoretech.github.io/helm
helm install my-nextjsapp icoretech/nextjs \
  --set web.image=yourusername/yourimage:tag \
  --set web.extraEnvs[0].name=MYVAR1,web.extraEnvs[0].value=value1 \
  --set web.extraEnvs[1].name=MYVAR2,web.extraEnvs[1].value=value2
```

## Configuration

The following table lists the configurable parameters of the Airbroke chart and their default values.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `nameOverride` | String to partially override app.fullname | `""` |
| `fullnameOverride` | String to fully override app.fullname | `""` |
| `web.image` | Docker image for the web application | `""` |
| `web.imagePullPolicy` | Image pull policy | `IfNotPresent` |
| `web.imagePullSecrets` | Image pull secrets, must be present in namespace | `""` |
| `web.terminationGracePeriodSeconds` | Grace period for shutdown | `0` |
| `web.replicaCount` | Number of replicas to run | `1` |
| `web.runtimeClassName` | Select the container runtime configuration | `` |
| `web.updateStrategy` | Update strategy to use | `{type: RollingUpdate, rollingUpdate: {maxUnavailable: 0, maxSurge: 1}}` |
| `web.cachePersistentVolume.enabled` | Enables a PersistentVolumeClaim for caching | `false` |
| `web.cachePersistentVolume.storageClass` | The storage class to use for the PVC | `""` |
| `web.cachePersistentVolume.existingClaim` | An existing PVC to use for the cache | `""` |
| `web.cachePersistentVolume.accessModes` | The access modes for the PVC | `["ReadWriteOnce"]` |
| `web.cachePersistentVolume.annotations` | Annotations to add to the PVC | `{}` |
| `web.cachePersistentVolume.size` | The size of the PVC | `1Gi` |
| `web.cachePersistentVolume.volumeMode` | The volume mode for the PVC | `""` |
| `web.cachePersistentVolume.mountPath` | The path to mount the volume in the container | `/app/.next/cache` |
| `web.hpa.enabled` | Enables the Horizontal Pod Autoscaler | `false` |
| `web.hpa.maxReplicas` | Maximum number of replicas for HPA | `10` |
| `web.hpa.cpu` | Average CPU usage per pod for HPA | |
| `web.hpa.memory` | Average memory usage per pod for HPA | |
| `web.hpa.requests` | Average HTTP requests per second per pod for HPA | |
| `web.ingress.enabled` | Enables Ingress | `false` |
| `web.ingress.ingressClassName` | Ingress class name | `nginx` |
| `web.ingress.annotations` | Annotations for Ingress | `{}` |
| `web.ingress.hosts` | Hosts for Ingress | `[]` |
| `web.ingress.tls` | TLS configuration for Ingress | `[]` |
| `web.service.enabled` | Enables service | `true` |
| `web.service.type` | Type of service | `ClusterIP` |
| `web.service.port` | Service port | `3000` |
| `web.livenessProbe.enabled` | Enables liveness probe | `false` |
| `web.livenessProbe.httpGet.endpoint` | Endpoint for liveness probe | `/api/hc?source=livenessProbe` |
| `web.livenessProbe.httpGet.httpHeaders` | HTTP headers for liveness probe | `[]` |
| `web.livenessProbe.initialDelaySeconds` | Initial delay for liveness probe | `0` |
| `web.livenessProbe.periodSeconds` | Period seconds for liveness probe | `10` |
| `web.livenessProbe.timeoutSeconds` | Timeout seconds for liveness probe | `5` |
| `web.livenessProbe.failureThreshold` | Failure threshold for liveness probe | `2` |
| `web.livenessProbe.successThreshold` | Success threshold for liveness probe | `1` |
| `web.readinessProbe.enabled` | Enables readiness probe | `false` |
| `web.readinessProbe.httpGet.endpoint` | Endpoint for readiness probe | `/api/hc?source=readinessProbe` |
| `web.readinessProbe.httpGet.httpHeaders` | HTTP headers for readiness probe | `[]` |
| `web.readinessProbe.initialDelaySeconds` | Initial delay for readiness probe | `0` |
| `web.readinessProbe.periodSeconds` | Period seconds for readiness probe | `10` |
| `web.readinessProbe.timeoutSeconds` | Timeout seconds for readiness probe | `5` |
| `web.readinessProbe.failureThreshold` | Failure threshold for readiness probe | `2` |
| `web.readinessProbe.successThreshold` | Success threshold for readiness probe | `1` |
| `web.resources` | CPU/Memory resource requests/limits | `{}` |
| `web.nodeSelector` | Node labels for pod assignment | `{}` |
| `web.tolerations` | Tolerations for pod assignment | `[]` |
| `web.affinity` | Affinity settings for pod assignment | `{}` |
| `web.extraEnvs` | Additional environment variables | `[]` |
| `web.podDisruptionBudget.enabled` | Enable PDB to ensure availability during disruptions. | `false` |
