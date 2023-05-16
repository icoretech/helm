# iCoreTech Helm Charts Repository

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/icoretech)](https://artifacthub.io/packages/search?repo=icoretech)

For detailed information on the individual charts, please navigate to the [charts](https://github.com/icoretech/helm/tree/main/charts) subdirectory.

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
  name: pgbouncer
  namespace: default
spec:
  releaseName: pgbouncer
  chart:
    spec:
      chart: pgbouncer
      version: ">= 1.7.7"
      sourceRef:
        kind: HelmRepository
        name: icoretech
        namespace: flux-system
  interval: 10m0s
  values:
    # ...
```
