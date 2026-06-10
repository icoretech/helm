# Multica Helm Chart

Deploy [Multica](https://github.com/multica-ai/multica), the open-source managed agents platform, on Kubernetes.

## Features

- Separate backend and frontend Deployments using upstream GHCR images
- Optional bundled PostgreSQL for evaluation and chart-testing
- External PostgreSQL mode for production deployments
- Optional bundled Redis for multi-backend realtime fanout, auth-token caches, daemon task-claim cache, and runtime-local skill queues
- Local upload PVC support and S3-compatible storage configuration
- Secret references for JWT, email, Google OAuth, metrics, database URL, GitHub App, Lark, and S3 credentials
- Ingress and Gateway API HTTPRoute support with backend path routing for CLI self-host setup
- Helm unit tests and install-safe CI values

## Important Runtime Note

The upstream `multica-web` image currently bakes its Next.js rewrites to `http://backend:8080` at build time. This chart creates a compatibility Service named `backend` by default so the official image works in Kubernetes. Because that Service name is intentionally unprefixed, run only one Multica release per namespace unless you disable the alias for a custom frontend image.

If you build a custom frontend image with a different `REMOTE_API_URL`, disable it:

```yaml
frontend:
  backendServiceAlias:
    enabled: false
```

## Prerequisites

- Kubernetes 1.24+
- Helm 3.10+
- For production: external PostgreSQL and a real `JWT_SECRET`
- For email delivery: Resend API credentials or an SMTP relay

## Install

```bash
helm repo add icoretech https://icoretech.github.io/helm
helm repo update
helm upgrade --install multica icoretech/multica \
  -n multica --create-namespace \
  --set backend.config.jwtSecret="replace-with-a-strong-secret-at-least-32-characters"
```

OCI:

```bash
helm upgrade --install multica oci://ghcr.io/icoretech/charts/multica \
  -n multica --create-namespace \
  --set backend.config.jwtSecret="replace-with-a-strong-secret-at-least-32-characters"
```

## Production Shape

For production, prefer external PostgreSQL and S3-compatible uploads:

```yaml
postgres:
  enabled: false

database:
  external:
    enabled: true
    # Required by the wait-for-Postgres init container when DATABASE_URL comes from a Secret.
    host: postgres.example.com
    urlFrom:
      secretKeyRef:
        name: multica-db
        key: DATABASE_URL

backend:
  config:
    frontendOrigin: https://multica.example.com
    publicUrl: https://multica.example.com
    jwtSecretRef:
      name: multica-auth
      key: JWT_SECRET
  email:
    resendApiKeyRef:
      name: multica-email
      key: RESEND_API_KEY
    resendFromEmail: noreply@example.com
    smtp:
      host: smtp.example.com
      port: 587
      # Use implicit for SMTPS/465, or leave empty for STARTTLS when advertised.
      tls: starttls
      # Set a real FQDN when strict public relays reject the container hostname.
      ehloName: mail.example.com
      usernameRef:
        name: multica-smtp
        key: SMTP_USERNAME
      passwordRef:
        name: multica-smtp
        key: SMTP_PASSWORD

storage:
  local:
    persistence:
      enabled: false
  s3:
    bucket: multica-uploads
    region: eu-west-1

redis:
  enabled: true
  persistence:
    size: 8Gi
```

When using the chart-managed Ingress or HTTPRoute, backend-owned paths such as `/health`, `/api`, `/auth`, `/uploads`, and `/ws` are routed directly to the backend Service by default. This is required by `multica setup self-host`, which probes `<server-url>/health`. If you manage Traefik `IngressRoute`, nginx snippets, or another external router outside the chart, mirror the same path split.

When using S3-compatible storage without `storage.s3.cloudfrontDomain`, Multica stores reader-facing URLs using the configured bucket endpoint. Configure the bucket with public `s3:GetObject` access for uploaded objects, set `storage.s3.cloudfrontDomain` with CloudFront signing support, or use `storage.attachments.downloadMode=proxy` when browsers and CLI clients cannot reach a private S3-compatible endpoint directly.

The backend startup probe gives cold installs time to wait for PostgreSQL and run migrations before liveness starts. Readiness uses `/readyz`, which checks PostgreSQL connectivity and the latest server migration. Liveness stays on `/health`, which only confirms the process is alive.

Backend pod annotations include a checksum of referenced Kubernetes Secret data so out-of-band rotations of `jwtSecretRef`, database URL, email, OAuth, Redis, GitHub, Lark, and S3 secrets roll the Deployment on the next `helm upgrade`. `helm template` and dry-run renders cannot read live Secrets, so they emit a stable placeholder checksum.

Leave `database.pool.maxConns` and `database.pool.minConns` empty unless you explicitly want `DATABASE_MAX_CONNS` / `DATABASE_MIN_CONNS` env vars to override Multica's own defaults and any `pool_max_conns` / `pool_min_conns` query parameters already embedded in `DATABASE_URL`.

Signup restrictions only apply to first-time signup. Existing users can always sign in again. To restrict first-time signup to explicit addresses or domains, keep `backend.config.allowSignup=true` and set `backend.config.allowedEmails` or `backend.config.allowedEmailDomains`. Setting `backend.config.allowSignup=false` blocks every new signup even when an email allowlist is present.

Set `backend.config.disableWorkspaceCreation=true` after bootstrapping the shared workspace when self-hosted users should only join by invitation. This maps to upstream `DISABLE_WORKSPACE_CREATION` and makes workspace creation fail for every caller.

Set `backend.config.authTokenTtl` only when you need to override Multica's default auth token lifetime. Behind a reverse proxy, configure `backend.rateLimits.auth.trustedProxies` for the public auth limiter and `backend.config.trustedProxies` for the autopilot webhook limiter so upstream rate limits see real client IPs instead of only the proxy address.

Email delivery can use Resend or an SMTP relay. SMTP is enabled when `backend.email.smtp.host` is set, and upstream Multica checks `SMTP_HOST` before Resend, so SMTP takes priority when both are configured. Port `465` is supported for implicit TLS; set `backend.email.smtp.tls=implicit` for non-standard SMTPS ports. For strict relays such as Google Workspace, set `backend.email.smtp.ehloName` to the FQDN the relay accepts. For production SMTP auth, prefer `backend.email.smtp.passwordRef` instead of inline `backend.email.smtp.password`.

GitHub App integration needs the app slug and webhook secret. Optionally set `backend.github.appId` with `backend.github.appPrivateKeyRef` so Multica can enrich the connected account name immediately after install. Store secrets in an existing Kubernetes Secret:

```yaml
backend:
  github:
    appSlug: multica-example
    webhookSecretRef:
      name: multica-github
      key: GITHUB_WEBHOOK_SECRET
    appId: "123456"
    appPrivateKeyRef:
      name: multica-github
      key: GITHUB_APP_PRIVATE_KEY
```

Lark/Feishu Bot integration is disabled until `backend.lark.secretKey` or `backend.lark.secretKeyRef` is set. Use a base64-encoded 32-byte key, for example `openssl rand -base64 32`. International Lark tenants should set both `backend.lark.httpBaseUrl` and `backend.lark.callbackBaseUrl` to `https://open.larksuite.com`; `backend.config.publicUrl` must point at the public API origin used by Lark binding prompts.

```yaml
backend:
  config:
    publicUrl: https://multica.example.com
  lark:
    secretKeyRef:
      name: multica-lark
      key: MULTICA_LARK_SECRET_KEY
    httpBaseUrl: https://open.larksuite.com
    callbackBaseUrl: https://open.larksuite.com
```

Usage rollup flags are read-path switches only. Set `backend.usageRollups.dailyEnabled` or `backend.usageRollups.dashboardEnabled` only after the external scheduler and historical backfill are in place.

For upgrades, `migrations.preUpgradeJob.enabled` runs the backend image as a Helm `pre-upgrade` hook before the Deployment rolls. It first runs `./migrate up`; if Multica refuses to drop legacy daily rollups because `task_usage_hourly` has not been seeded yet, the hook runs `./backfill_task_usage_hourly` and retries `./migrate up`. This matches the upstream `v0.3.5` self-host upgrade order while keeping the regular backend entrypoint unchanged.

By default, `usageRollups.cronJob.enabled` creates a Kubernetes CronJob that calls `rollup_task_usage_hourly()` every five minutes. Each job waits for the migrated rollup function before calling it, so fresh installs do not record failed jobs while the backend is still applying migrations. This keeps the ongoing scheduler in Kubernetes instead of requiring the PostgreSQL `pg_cron` extension. If your database already runs the upstream `pg_cron` entry, disable the chart CronJob to avoid duplicate work:

```yaml
usageRollups:
  cronJob:
    enabled: false
```

## Agent Execution Model

This chart deploys the Multica server layer only: backend, frontend, database wiring, and upload storage. Agent execution still happens through Multica daemons running on separate machines where Codex, Claude Code, OpenCode, or another supported coding tool is installed.

Daemon-only environment variables don't belong in this server-layer chart. Keep values such as `MULTICA_CLAUDE_ARGS`, `MULTICA_CODEX_ARGS`, and `MULTICA_TASK_SLOT` on daemon hosts or daemon workloads, not in backend or frontend pod configuration.

## Configuration Reference

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| backend.affinity | object | `{}` | Backend affinity. |
| backend.autoscaling.enabled | bool | `false` | Enable backend HPA. |
| backend.autoscaling.maxReplicas | int | `5` | Maximum backend replicas. |
| backend.autoscaling.minReplicas | int | `1` | Minimum backend replicas. |
| backend.autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage. |
| backend.autoscaling.targetMemoryUtilizationPercentage | string | `nil` | Target memory utilization percentage. |
| backend.config.allowSignup | bool | `true` | Signup master switch. Keep true when using allowedEmails or allowedEmailDomains; set false only to block all first-time signup. |
| backend.config.allowedEmailDomains | string | `""` | First-time signup domain allowlist, comma-separated. Existing users can still sign in even if their domain is removed from the allowlist. |
| backend.config.allowedEmails | string | `""` | Explicit first-time signup email allowlist, comma-separated. Existing users can still sign in even if removed from the allowlist. |
| backend.config.allowedOrigins | string | `""` | Additional WebSocket origins, comma-separated. |
| backend.config.analyticsDisabled | bool | `true` | Disable backend/frontend analytics. Defaults to true for self-host privacy. |
| backend.config.analyticsEnvironment | string | `""` | Optional PostHog environment property override. Empty lets Multica derive it from APP_ENV. |
| backend.config.appEnv | string | `"production"` | Runtime environment. Keep `production` on public deployments. |
| backend.config.authTokenTtl | string | `""` | Optional AUTH_TOKEN_TTL override. Empty uses Multica's default auth token lifetime. |
| backend.config.cookieDomain | string | `""` | Optional cookie Domain attribute. Leave empty for single-host deployments. |
| backend.config.corsAllowedOrigins | string | `""` | Additional CORS origins, comma-separated. |
| backend.config.devVerificationCode | string | `""` | Fixed local test verification code. Keep empty in production. |
| backend.config.disableWorkspaceCreation | bool | `false` | Disable workspace creation globally. Bootstrap the shared workspace with this false, then set true so users can only join by invitation. |
| backend.config.frontendOrigin | string | `"http://localhost:3000"` | Public frontend origin. Required for production links, cookies, CORS, and WebSocket origin checks. |
| backend.config.jwtSecret | string | `"change-me-in-production"` | JWT signing secret. Replace in production or use jwtSecretRef. |
| backend.config.jwtSecretRef.key | string | `""` | Secret key for JWT_SECRET. |
| backend.config.jwtSecretRef.name | string | `""` | Existing secret containing JWT_SECRET. |
| backend.config.metricsAddr | string | `""` | Prometheus metrics listener, e.g. `127.0.0.1:9090`. Empty disables it. |
| backend.config.port | int | `8080` | Backend bind port. |
| backend.config.posthogApiKey | string | `""` | PostHog API key when analytics are enabled. |
| backend.config.posthogHost | string | `"https://us.i.posthog.com"` |  |
| backend.config.publicUrl | string | `""` | Public API URL without a trailing slash. Empty defaults to frontendOrigin, which matches the chart-managed same-origin routes. |
| backend.config.realtimeMetricsToken | string | `""` | Token required to expose `/health/realtime` through a proxy. |
| backend.config.realtimeMetricsTokenRef.key | string | `""` | Secret key for REALTIME_METRICS_TOKEN. |
| backend.config.realtimeMetricsTokenRef.name | string | `""` | Existing secret containing REALTIME_METRICS_TOKEN. |
| backend.config.trustedProxies | string | `""` | Comma-separated CIDRs whose X-Forwarded-For/X-Real-IP headers are trusted by Multica's autopilot webhook limiter. |
| backend.deployment.progressDeadlineSeconds | int | `600` | Time in seconds for the Deployment controller to wait before marking a rollout failed. |
| backend.deployment.strategy.type | string | `"Recreate"` | Deployment strategy. `Recreate` avoids RWO upload PVC multi-attach deadlocks. |
| backend.email.resendApiKey | string | `""` | Resend API key. When empty, Multica prints verification codes to stdout. |
| backend.email.resendApiKeyRef.key | string | `""` | Secret key for RESEND_API_KEY. |
| backend.email.resendApiKeyRef.name | string | `""` | Existing secret containing RESEND_API_KEY. |
| backend.email.resendFromEmail | string | `"noreply@multica.ai"` | Sender address for verification emails. |
| backend.email.smtp.ehloName | string | `""` | EHLO/HELO hostname announced to strict SMTP relays. Empty lets Multica use the backend container hostname. |
| backend.email.smtp.host | string | `""` | SMTP relay host. When empty, Multica uses Resend or stdout fallback. |
| backend.email.smtp.password | string | `""` | Optional SMTP auth password. |
| backend.email.smtp.passwordRef.key | string | `""` | Secret key for SMTP_PASSWORD. |
| backend.email.smtp.passwordRef.name | string | `""` | Existing secret containing SMTP_PASSWORD. |
| backend.email.smtp.port | int | `25` | SMTP relay port. Port 465 auto-enables implicit TLS unless smtp.tls overrides the mode. |
| backend.email.smtp.tls | string | `""` | SMTP TLS mode. Empty/starttls uses STARTTLS when advertised; implicit/smtps/ssl starts TLS immediately. |
| backend.email.smtp.tlsInsecure | bool | `false` | Skip TLS certificate verification for SMTP STARTTLS. |
| backend.email.smtp.username | string | `""` | Optional SMTP auth username. |
| backend.email.smtp.usernameRef.key | string | `""` | Secret key for SMTP_USERNAME. |
| backend.email.smtp.usernameRef.name | string | `""` | Existing secret containing SMTP_USERNAME. |
| backend.envFrom | list | `[]` | Extra backend envFrom refs. |
| backend.extraEnv | list | `[]` | Extra backend env vars. Managed env names are rejected to avoid silent overrides. |
| backend.github.appId | string | `""` | Optional GitHub App ID used to enrich connected account names after install. |
| backend.github.appPrivateKey | string | `""` | Optional GitHub App private key PEM. Prefer appPrivateKeyRef for production deployments. |
| backend.github.appPrivateKeyRef.key | string | `""` | Secret key for GITHUB_APP_PRIVATE_KEY. |
| backend.github.appPrivateKeyRef.name | string | `""` | Existing secret containing GITHUB_APP_PRIVATE_KEY. |
| backend.github.appSlug | string | `""` | GitHub App slug. |
| backend.github.webhookSecret | string | `""` | GitHub App webhook secret. Prefer webhookSecretRef for production deployments. |
| backend.github.webhookSecretRef.key | string | `""` | Secret key for GITHUB_WEBHOOK_SECRET. |
| backend.github.webhookSecretRef.name | string | `""` | Existing secret containing GITHUB_WEBHOOK_SECRET. |
| backend.google.clientId | string | `""` | Google OAuth client ID. |
| backend.google.clientIdRef.key | string | `""` | Secret key for GOOGLE_CLIENT_ID. |
| backend.google.clientIdRef.name | string | `""` | Existing secret containing GOOGLE_CLIENT_ID. |
| backend.google.clientSecret | string | `""` | Google OAuth client secret. |
| backend.google.clientSecretRef.key | string | `""` | Secret key for GOOGLE_CLIENT_SECRET. |
| backend.google.clientSecretRef.name | string | `""` | Existing secret containing GOOGLE_CLIENT_SECRET. |
| backend.google.redirectUri | string | `"http://localhost:3000/auth/callback"` | Google OAuth redirect URI. |
| backend.image.pullPolicy | string | `"IfNotPresent"` | Backend image pull policy. |
| backend.image.repository | string | `"ghcr.io/multica-ai/multica-backend"` | Backend image repository. |
| backend.image.tag | string | `""` | Backend image tag override. Defaults to chart appVersion. |
| backend.lark.callbackBaseUrl | string | `""` | Optional Lark long-connection callback bootstrap base URL. Set to https://open.larksuite.com for international Lark tenants. |
| backend.lark.httpBaseUrl | string | `""` | Optional Lark Open Platform API base URL. Set to https://open.larksuite.com for international Lark tenants. |
| backend.lark.registrationDomain | string | `""` | Optional initial device-flow registration host override. |
| backend.lark.registrationLarkDomain | string | `""` | Optional Lark international device-flow registration host override. |
| backend.lark.secretKey | string | `""` | Base64-encoded 32-byte key enabling Lark/Feishu Bot integration and encrypting Bot app secrets at rest. Prefer secretKeyRef in production. |
| backend.lark.secretKeyRef.key | string | `""` | Secret key for MULTICA_LARK_SECRET_KEY. |
| backend.lark.secretKeyRef.name | string | `""` | Existing secret containing MULTICA_LARK_SECRET_KEY. |
| backend.nodeSelector | object | `{}` | Backend node selector. |
| backend.podAnnotations | object | `{}` | Pod annotations for backend pods. |
| backend.podLabels | object | `{}` | Pod labels for backend pods. |
| backend.podSecurityContext | object | `{}` | Pod security context for backend pods. |
| backend.rateLimits.auth.maxPerMinute | string | `nil` | Optional RATE_LIMIT_AUTH override for `/auth/send-code` and `/auth/google` requests per IP per minute. Empty uses Multica's default. |
| backend.rateLimits.auth.trustedProxies | string | `""` | Comma-separated CIDRs whose X-Forwarded-For header is trusted by the auth rate limiter. |
| backend.rateLimits.auth.verifyMaxPerMinute | string | `nil` | Optional RATE_LIMIT_AUTH_VERIFY override for `/auth/verify-code` requests per IP per minute. Empty uses Multica's default. |
| backend.replicaCount | int | `1` | Number of backend replicas. |
| backend.resources | object | `{}` | Backend resources. |
| backend.securityContext | object | `{}` | Container security context for the backend container. |
| backend.service.annotations | object | `{}` | Backend Service annotations. |
| backend.service.nodePort | string | `nil` | Optional nodePort when service.type is NodePort/LoadBalancer. |
| backend.service.port | int | `8080` | Backend Service port. |
| backend.service.targetPort | int | `8080` | Backend container port. |
| backend.service.type | string | `"ClusterIP"` | Backend Service type. |
| backend.tolerations | list | `[]` | Backend tolerations. |
| backend.usageRollups.dailyEnabled | bool | `false` | Enable runtime usage reads from the daily rollup table after external backfill/scheduler setup is complete. |
| backend.usageRollups.dashboardEnabled | bool | `false` | Enable dashboard usage reads from the dashboard rollup table after external backfill/scheduler setup is complete. |
| backend.volumeMounts | list | `[]` | Additional backend volume mounts. |
| backend.volumes | list | `[]` | Additional backend volumes. |
| database.external.enabled | bool | `false` | Enable external PostgreSQL mode. When enabled, set postgres.enabled=false. |
| database.external.host | string | `""` | External PostgreSQL host. Required for waitForReady when using urlFrom; optional with url because the chart can derive the host from the URL. |
| database.external.name | string | `"multica"` | External PostgreSQL database name. |
| database.external.password | string | `""` | External PostgreSQL password. |
| database.external.port | int | `5432` | External PostgreSQL port. |
| database.external.sslMode | string | `"disable"` | SSL mode appended to generated DATABASE_URL. |
| database.external.url | string | `""` | Full PostgreSQL connection URL. |
| database.external.urlFrom.secretKeyRef | object | `{"key":"","name":""}` | Existing secret containing DATABASE_URL. |
| database.external.username | string | `""` | External PostgreSQL username. |
| database.internal.port | int | `5432` | Internal PostgreSQL service port. |
| database.internal.serviceName | string | `""` | Override internal PostgreSQL service name. Defaults to `<release>-postgres`. |
| database.pool.maxConns | string | `nil` | Optional DATABASE_MAX_CONNS env override. Leave empty to honor DATABASE_URL pool_max_conns or Multica defaults. |
| database.pool.minConns | string | `nil` | Optional DATABASE_MIN_CONNS env override. Leave empty to honor DATABASE_URL pool_min_conns or Multica defaults. |
| database.waitForReady.enabled | bool | `true` | Wait for PostgreSQL TCP readiness before starting the backend. |
| database.waitForReady.image | string | `"busybox:1.38"` | Init container image used for DB readiness checks. |
| database.waitForReady.imagePullPolicy | string | `"IfNotPresent"` | Init container image pull policy. |
| database.waitForReady.periodSeconds | int | `2` | Poll interval in seconds. |
| database.waitForReady.timeoutSeconds | int | `180` | Max seconds to wait for DB readiness. |
| frontend.affinity | object | `{}` | Frontend affinity. |
| frontend.autoscaling.enabled | bool | `false` | Enable frontend HPA. |
| frontend.autoscaling.maxReplicas | int | `5` | Maximum frontend replicas. |
| frontend.autoscaling.minReplicas | int | `1` | Minimum frontend replicas. |
| frontend.autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage. |
| frontend.autoscaling.targetMemoryUtilizationPercentage | string | `nil` | Target memory utilization percentage. |
| frontend.backendServiceAlias.annotations | object | `{}` | Compatibility Service annotations. |
| frontend.backendServiceAlias.enabled | bool | `true` | Create a Service named `backend` because upstream multica-web images bake Next.js rewrites to `http://backend:8080`. The unprefixed name means one Multica release per namespace unless you disable this for a custom frontend image. |
| frontend.backendServiceAlias.name | string | `"backend"` | Compatibility Service name. |
| frontend.envFrom | list | `[]` | Extra frontend envFrom refs. |
| frontend.extraEnv | list | `[]` | Extra frontend env vars. The official image bakes API rewrites at build time; use these only for custom images or generic runtime config. |
| frontend.image.pullPolicy | string | `"IfNotPresent"` | Frontend image pull policy. |
| frontend.image.repository | string | `"ghcr.io/multica-ai/multica-web"` | Frontend image repository. |
| frontend.image.tag | string | `""` | Frontend image tag override. Defaults to chart appVersion. |
| frontend.nodeSelector | object | `{}` | Frontend node selector. |
| frontend.podAnnotations | object | `{}` | Pod annotations for frontend pods. |
| frontend.podLabels | object | `{}` | Pod labels for frontend pods. |
| frontend.podSecurityContext | object | `{}` | Pod security context for frontend pods. |
| frontend.replicaCount | int | `1` | Number of frontend replicas. |
| frontend.resources | object | `{}` | Frontend resources. |
| frontend.securityContext | object | `{}` | Container security context for the frontend container. |
| frontend.service.annotations | object | `{}` | Frontend Service annotations. |
| frontend.service.externalTrafficPolicy | string | `nil` | External traffic policy. |
| frontend.service.loadBalancerIP | string | `nil` | Optional LoadBalancer IP. |
| frontend.service.loadBalancerSourceRanges | list | `[]` | Optional CIDRs allowed via LoadBalancer. |
| frontend.service.nodePort | string | `nil` | Optional nodePort when service.type is NodePort/LoadBalancer. |
| frontend.service.port | int | `80` | Frontend Service port. |
| frontend.service.targetPort | int | `3000` | Frontend container port. |
| frontend.service.type | string | `"ClusterIP"` | Frontend Service type. |
| frontend.tolerations | list | `[]` | Frontend tolerations. |
| fullnameOverride | string | `""` | Override fully-qualified release name. |
| httpRoute.annotations | object | `{}` | HTTPRoute annotations. |
| httpRoute.backendMatches.enabled | bool | `true` | Route backend-owned paths directly to the backend Service. Required for CLI `multica setup self-host`, which probes `/health`. |
| httpRoute.backendMatches.matches | list | `[{"path":{"type":"Exact","value":"/health"}},{"path":{"type":"PathPrefix","value":"/health/"}},{"path":{"type":"Exact","value":"/ws"}},{"path":{"type":"Exact","value":"/api"}},{"path":{"type":"PathPrefix","value":"/api/"}},{"path":{"type":"Exact","value":"/auth"}},{"path":{"type":"PathPrefix","value":"/auth/"}},{"path":{"type":"Exact","value":"/uploads"}},{"path":{"type":"PathPrefix","value":"/uploads/"}}]` | Backend HTTPRoute matches emitted before frontend matches. |
| httpRoute.enabled | bool | `false` | Enable Gateway API HTTPRoute for Multica. |
| httpRoute.hostnames | list | `[]` | Optional HTTPRoute hostnames. |
| httpRoute.matches | list | `[{"path":{"type":"PathPrefix","value":"/"}}]` | Match rules for HTTPRoute. |
| httpRoute.parentRefs | list | `[]` | ParentRefs for HTTPRoute. Required when enabled. |
| imagePullSecrets | list | `[]` | Shared image pull secrets. |
| ingress.annotations | object | `{}` | Ingress annotations. |
| ingress.backendPaths.enabled | bool | `true` | Route backend-owned paths directly to the backend Service. Required for CLI `multica setup self-host`, which probes `/health`. |
| ingress.backendPaths.paths | list | `[{"path":"/health","pathType":"Prefix"},{"path":"/ws","pathType":"Exact"},{"path":"/api","pathType":"Prefix"},{"path":"/auth","pathType":"Prefix"},{"path":"/uploads","pathType":"Prefix"}]` | Backend paths to expose through Ingress before frontend catch-all paths. |
| ingress.className | string | `""` | IngressClass name. |
| ingress.enabled | bool | `false` | Enable Ingress for Multica. |
| ingress.hosts | list | `[]` | Ingress hosts and paths. |
| ingress.tls | list | `[]` | Ingress TLS entries. |
| livenessProbe.backend.failureThreshold | int | `6` |  |
| livenessProbe.backend.httpGet.path | string | `"/health"` |  |
| livenessProbe.backend.httpGet.port | string | `"http"` |  |
| livenessProbe.backend.initialDelaySeconds | int | `10` |  |
| livenessProbe.backend.periodSeconds | int | `10` |  |
| livenessProbe.backend.successThreshold | int | `1` |  |
| livenessProbe.backend.timeoutSeconds | int | `3` |  |
| livenessProbe.frontend.failureThreshold | int | `6` |  |
| livenessProbe.frontend.httpGet.path | string | `"/"` |  |
| livenessProbe.frontend.httpGet.port | string | `"http"` |  |
| livenessProbe.frontend.initialDelaySeconds | int | `10` |  |
| livenessProbe.frontend.periodSeconds | int | `10` |  |
| livenessProbe.frontend.successThreshold | int | `1` |  |
| livenessProbe.frontend.timeoutSeconds | int | `3` |  |
| migrations.preUpgradeJob.backfillTaskUsageHourlyOnFailure | bool | `true` | Retry `migrate up` after running `backfill_task_usage_hourly` when the first migration pass fails. |
| migrations.preUpgradeJob.backoffLimit | int | `1` | Job backoff limit. |
| migrations.preUpgradeJob.enabled | bool | `true` | Run a Helm pre-upgrade Job with the backend image before rolling the Deployment. |
| migrations.preUpgradeJob.hookDeletePolicy | string | `"before-hook-creation,hook-succeeded"` | Hook delete policy for the migration Job. |
| migrations.preUpgradeJob.hookWeight | int | `-5` | Helm hook weight for the migration Job. |
| migrations.preUpgradeJob.podAnnotations | object | `{}` | Pod annotations for the migration Job. |
| migrations.preUpgradeJob.resources | object | `{}` | Migration Job resources. |
| migrations.preUpgradeJob.ttlSecondsAfterFinished | int | `300` | Seconds to keep the finished Job. Set null to omit. |
| nameOverride | string | `""` | Override chart name. |
| postgres.auth.database | string | `"multica"` |  |
| postgres.auth.password | string | `"multica"` |  |
| postgres.auth.username | string | `"multica"` |  |
| postgres.enabled | bool | `true` |  |
| postgres.image.imagePullPolicy | string | `"IfNotPresent"` |  |
| postgres.image.repository | string | `"pgvector/pgvector"` |  |
| postgres.image.tag | string | `"pg17"` |  |
| postgres.persistence.enabled | bool | `true` |  |
| postgres.persistence.size | string | `"8Gi"` |  |
| readinessProbe.backend.failureThreshold | int | `6` |  |
| readinessProbe.backend.httpGet.path | string | `"/readyz"` |  |
| readinessProbe.backend.httpGet.port | string | `"http"` |  |
| readinessProbe.backend.initialDelaySeconds | int | `10` |  |
| readinessProbe.backend.periodSeconds | int | `10` |  |
| readinessProbe.backend.successThreshold | int | `1` |  |
| readinessProbe.backend.timeoutSeconds | int | `3` |  |
| readinessProbe.frontend.failureThreshold | int | `6` |  |
| readinessProbe.frontend.httpGet.path | string | `"/"` |  |
| readinessProbe.frontend.httpGet.port | string | `"http"` |  |
| readinessProbe.frontend.initialDelaySeconds | int | `5` |  |
| readinessProbe.frontend.periodSeconds | int | `10` |  |
| readinessProbe.frontend.successThreshold | int | `1` |  |
| readinessProbe.frontend.timeoutSeconds | int | `3` |  |
| realtime.redisUrl | string | `""` | Redis connection URL for multi-backend realtime fanout, auth-token caches, daemon task-claim cache, and runtime-local skill queues. Leave empty for single-backend in-memory mode or when using bundled Redis. |
| realtime.redisUrlRef.key | string | `""` | Secret key for REDIS_URL. |
| realtime.redisUrlRef.name | string | `""` | Existing secret containing REDIS_URL. |
| redis.architecture | string | `"standalone"` |  |
| redis.auth.enabled | bool | `true` |  |
| redis.enabled | bool | `false` | Enable bundled Redis for multi-backend realtime fanout, auth-token caches, daemon task-claim cache, and runtime-local skill queues. |
| redis.persistence.enabled | bool | `true` |  |
| redis.persistence.size | string | `"8Gi"` |  |
| serviceAccount.annotations | object | `{}` | Service account annotations. |
| serviceAccount.create | bool | `true` | Create a service account for Multica pods. |
| serviceAccount.name | string | `""` | Service account name. |
| startupProbe.backend.failureThreshold | int | `30` |  |
| startupProbe.backend.httpGet.path | string | `"/health"` |  |
| startupProbe.backend.httpGet.port | string | `"http"` |  |
| startupProbe.backend.periodSeconds | int | `10` |  |
| startupProbe.backend.successThreshold | int | `1` |  |
| startupProbe.backend.timeoutSeconds | int | `3` |  |
| storage.attachments.downloadMode | string | `"auto"` | Attachment download behavior: auto, cloudfront, presign, or proxy. |
| storage.attachments.downloadUrlTtl | string | `"30m"` | TTL for CloudFront signed URLs and S3 presigned attachment download URLs. |
| storage.local.baseUrl | string | `""` | Public base URL for local uploads. Empty returns relative `/uploads/...` paths. |
| storage.local.persistence.accessModes | list | `["ReadWriteOnce"]` | PVC access modes. |
| storage.local.persistence.annotations | object | `{}` | PVC annotations. |
| storage.local.persistence.enabled | bool | `true` | Persist local uploads with a PVC. Use S3 for multi-replica production deployments. |
| storage.local.persistence.existingClaim | string | `""` | Existing PVC name. |
| storage.local.persistence.size | string | `"10Gi"` | PVC size. |
| storage.local.persistence.storageClass | string | `""` | PVC storage class. |
| storage.local.uploadDir | string | `"/app/data/uploads"` | Local upload directory inside the backend container. |
| storage.s3.accessKeyId | string | `""` | AWS access key ID. |
| storage.s3.accessKeyIdRef.key | string | `""` | Secret key for AWS_ACCESS_KEY_ID. |
| storage.s3.accessKeyIdRef.name | string | `""` | Existing secret containing AWS_ACCESS_KEY_ID. |
| storage.s3.bucket | string | `""` | S3 bucket. When set, Multica uses S3-compatible storage instead of local disk for uploads. |
| storage.s3.cloudfrontDomain | string | `""` | CloudFront domain for signed/download URLs. |
| storage.s3.cloudfrontKeyPairId | string | `""` | CloudFront key pair ID. |
| storage.s3.cloudfrontPrivateKey | string | `""` | CloudFront private key. |
| storage.s3.cloudfrontPrivateKeyRef.key | string | `""` | Secret key for CLOUDFRONT_PRIVATE_KEY. |
| storage.s3.cloudfrontPrivateKeyRef.name | string | `""` | Existing secret containing CLOUDFRONT_PRIVATE_KEY. |
| storage.s3.cloudfrontPrivateKeySecret | string | `""` | AWS Secrets Manager secret name for CLOUDFRONT_PRIVATE_KEY. |
| storage.s3.endpointUrl | string | `""` | S3-compatible endpoint URL, e.g. MinIO/R2/Wasabi. |
| storage.s3.region | string | `"us-west-2"` | S3 region. |
| storage.s3.secretAccessKey | string | `""` | AWS secret access key. |
| storage.s3.secretAccessKeyRef.key | string | `""` | Secret key for AWS_SECRET_ACCESS_KEY. |
| storage.s3.secretAccessKeyRef.name | string | `""` | Existing secret containing AWS_SECRET_ACCESS_KEY. |
| tests.enabled | bool | `true` | Enable Helm test pod. |
| tests.image.pullPolicy | string | `"IfNotPresent"` | Test image pull policy. |
| tests.image.repository | string | `"busybox"` | Test image repository. |
| tests.image.tag | string | `"1.38"` | Test image tag. |
| usageRollups.cronJob.backoffLimit | int | `1` | Job backoff limit. |
| usageRollups.cronJob.concurrencyPolicy | string | `"Forbid"` | CronJob concurrency policy. Forbid pairs with the database advisory lock to avoid overlapping rollups. |
| usageRollups.cronJob.enabled | bool | `true` | Run rollup_task_usage_hourly() on a Kubernetes CronJob instead of requiring pg_cron in PostgreSQL. |
| usageRollups.cronJob.failedJobsHistoryLimit | int | `3` | Failed Job history limit. |
| usageRollups.cronJob.image.pullPolicy | string | `"IfNotPresent"` | PostgreSQL client image pull policy. |
| usageRollups.cronJob.image.repository | string | `"postgres"` | PostgreSQL client image repository used to call the rollup SQL function. |
| usageRollups.cronJob.image.tag | string | `"18-alpine"` | PostgreSQL client image tag. |
| usageRollups.cronJob.podAnnotations | object | `{}` | Pod annotations for the rollup CronJob. |
| usageRollups.cronJob.resources | object | `{}` | Rollup CronJob resources. |
| usageRollups.cronJob.schedule | string | `"*/5 * * * *"` | Cron schedule for the hourly usage rollup worker. |
| usageRollups.cronJob.startingDeadlineSeconds | int | `300` | Seconds after a missed schedule when the job may still start. Set null to omit. |
| usageRollups.cronJob.successfulJobsHistoryLimit | int | `3` | Successful Job history limit. |
