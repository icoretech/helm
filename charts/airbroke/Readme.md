# Airbroke Helm Chart

This Helm chart deploys Airbroke, a modern, React-based open source error catcher web application.

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
| `web.image` | Docker image for the web application | `ghcr.io/icoretech/airbroke:1.1.2` |
| `web.replicaCount` | Number of replicas to run | `1` |
| `web.updateStrategy` | Update strategy to use | `{type: RollingUpdate, rollingUpdate: {maxUnavailable: 0, maxSurge: 1}}` |
| `web.hpa.enabled` | Enables the Horizontal Pod Autoscaler | `false` |
| `web.ingress.enabled` | Enables Ingress | `false` |
| `pgbouncer.enabled` | Enables Pgbouncer, a lightweight connection pooler for PostgreSQL | `false` |

Please note, this is a simplified version of the parameters for the purpose of this README. For full configuration options, please refer to the `values.yaml` file.

You can specify additional environment variables using the `extraEnvs` parameter.

### Pgbouncer

Pgbouncer, a lightweight connection pooler for PostgreSQL, can be enabled using the `pgbouncer.enabled` parameter. You can customize the Pgbouncer configuration under `pgbouncer.config`.
