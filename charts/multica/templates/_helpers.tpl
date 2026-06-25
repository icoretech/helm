{{/* Expand the name of the chart. */}}
{{- define "multica.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully-qualified app name. */}}
{{- define "multica.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Create chart label value. */}}
{{- define "multica.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels. */}}
{{- define "multica.labels" -}}
helm.sh/chart: {{ include "multica.chart" . }}
{{ include "multica.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Selector labels. */}}
{{- define "multica.selectorLabels" -}}
app.kubernetes.io/name: {{ include "multica.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Component selector labels. */}}
{{- define "multica.componentSelectorLabels" -}}
{{ include "multica.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/* Service account name. */}}
{{- define "multica.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "multica.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Backend service name. */}}
{{- define "multica.backendServiceName" -}}
{{- printf "%s-backend" (include "multica.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Frontend service name. */}}
{{- define "multica.frontendServiceName" -}}
{{- include "multica.fullname" . }}
{{- end }}

{{/* Feature flag ConfigMap name. */}}
{{- define "multica.featureFlagsConfigMapName" -}}
{{- printf "%s-feature-flags" (include "multica.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Feature flag ConfigMap key. */}}
{{- define "multica.featureFlagsConfigMapKey" -}}
{{- if .Values.backend.featureFlags.existingConfigMap.name -}}
{{- .Values.backend.featureFlags.existingConfigMap.key -}}
{{- else -}}
feature-flags.yaml
{{- end -}}
{{- end }}

{{/* Feature flag ConfigMap source name. */}}
{{- define "multica.featureFlagsConfigMapSourceName" -}}
{{- if .Values.backend.featureFlags.existingConfigMap.name -}}
{{- .Values.backend.featureFlags.existingConfigMap.name -}}
{{- else -}}
{{- include "multica.featureFlagsConfigMapName" . -}}
{{- end -}}
{{- end }}

{{/* Upload PVC name. */}}
{{- define "multica.uploadsClaimName" -}}
{{- if .Values.storage.local.persistence.existingClaim }}
{{- .Values.storage.local.persistence.existingClaim -}}
{{- else -}}
{{- printf "%s-uploads" (include "multica.fullname" .) -}}
{{- end -}}
{{- end }}

{{/* Default service name of the internal Postgres dependency. */}}
{{- define "multica.postgres.serviceName" -}}
{{- if .Values.database.internal.serviceName -}}
{{- .Values.database.internal.serviceName -}}
{{- else -}}
{{- printf "%s-postgres" .Release.Name -}}
{{- end -}}
{{- end }}

{{/* Default full name of the bundled Redis dependency. */}}
{{- define "multica.redis.fullname" -}}
{{- if .Values.redis.fullnameOverride -}}
{{- .Values.redis.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default "redis" .Values.redis.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/* Default namespace of the bundled Redis dependency. */}}
{{- define "multica.redis.namespace" -}}
{{- default .Release.Namespace .Values.redis.namespaceOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/* Plain bundled Redis URL used when Redis auth is disabled. */}}
{{- define "multica.redis.unauthenticatedUrl" -}}
{{- $scheme := ternary "rediss" "redis" .Values.redis.tls.enabled -}}
{{- $port := ternary .Values.redis.tls.port .Values.redis.service.port .Values.redis.tls.enabled -}}
{{- printf "%s://%s.%s.svc:%v" $scheme (include "multica.redis.fullname" .) (include "multica.redis.namespace" .) $port -}}
{{- end }}

{{/* Generated DATABASE_URL for internal or simple external mode. */}}
{{- define "multica.databaseUrl" -}}
{{- if .Values.database.external.enabled -}}
  {{- if .Values.database.external.url -}}
    {{- .Values.database.external.url -}}
  {{- else -}}
    {{- printf "postgres://%s:%s@%s:%v/%s?sslmode=%s" .Values.database.external.username .Values.database.external.password .Values.database.external.host .Values.database.external.port .Values.database.external.name .Values.database.external.sslMode -}}
  {{- end -}}
{{- else -}}
  {{- printf "postgres://%s:%s@%s:%v/%s?sslmode=disable" .Values.postgres.auth.username .Values.postgres.auth.password (include "multica.postgres.serviceName" .) .Values.database.internal.port .Values.postgres.auth.database -}}
{{- end -}}
{{- end }}

{{/* Database host for readiness wait. */}}
{{- define "multica.databaseHost" -}}
{{- if .Values.database.external.enabled -}}
  {{- if .Values.database.external.host -}}
    {{- .Values.database.external.host -}}
  {{- else if .Values.database.external.url -}}
    {{- $parsed := urlParse .Values.database.external.url -}}
    {{- regexReplaceAll ":[0-9]+$" $parsed.host "" -}}
  {{- end -}}
{{- else -}}
{{- include "multica.postgres.serviceName" . -}}
{{- end -}}
{{- end }}

{{/* Database port for readiness wait. */}}
{{- define "multica.databasePort" -}}
{{- if .Values.database.external.enabled -}}
  {{- if and .Values.database.external.url (not .Values.database.external.host) -}}
    {{- $parsed := urlParse .Values.database.external.url -}}
    {{- $port := regexFind ":[0-9]+$" $parsed.host -}}
    {{- if $port -}}
      {{- trimPrefix ":" $port -}}
    {{- else -}}
      {{- .Values.database.external.port -}}
    {{- end -}}
  {{- else -}}
    {{- .Values.database.external.port -}}
  {{- end -}}
{{- else -}}
{{- .Values.database.internal.port -}}
{{- end -}}
{{- end }}

{{- define "multica.backendSecretChecksumInput" -}}
{{- $root := . -}}
{{- $refs := list -}}
{{- with .Values.database.external.urlFrom.secretKeyRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.realtime.redisUrlRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- if and .Values.redis.enabled .Values.redis.auth.enabled (not .Values.realtime.redisUrl) (not .Values.realtime.redisUrlRef.name) }}{{- $refs = append $refs (dict "name" (include "multica.redis.fullname" .) "key" "uri") }}{{- end }}
{{- with .Values.backend.config.jwtSecretRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.backend.config.realtimeMetricsTokenRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.backend.email.resendApiKeyRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.backend.email.smtp.usernameRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.backend.email.smtp.passwordRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.backend.google.clientIdRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.backend.google.clientSecretRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.backend.github.webhookSecretRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.backend.github.appPrivateKeyRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.backend.lark.secretKeyRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.backend.slack.secretKeyRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.storage.s3.accessKeyIdRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.storage.s3.secretAccessKeyRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- with .Values.storage.s3.cloudfrontPrivateKeyRef }}{{- if .name }}{{- $refs = append $refs (dict "name" .name "key" .key) }}{{- end }}{{- end }}
{{- range $refs }}
- name: {{ .name | quote }}
  key: {{ .key | quote }}
  data:
    {{- $secret := lookup "v1" "Secret" $root.Release.Namespace .name }}
    {{- if $secret }}
    {{- toYaml $secret.data | nindent 4 }}
    {{- else }}
    {}
    {{- end }}
{{- end }}
{{- end }}

{{- define "multica.featureFlagsChecksumInput" -}}
rules:
  {{- toYaml .Values.backend.featureFlags.rules | nindent 2 }}
existingConfigMap:
  name: {{ .Values.backend.featureFlags.existingConfigMap.name | quote }}
  key: {{ .Values.backend.featureFlags.existingConfigMap.key | quote }}
  data:
    {{- if .Values.backend.featureFlags.existingConfigMap.name }}
    {{- $cm := lookup "v1" "ConfigMap" .Release.Namespace .Values.backend.featureFlags.existingConfigMap.name }}
    {{- if $cm }}
    {{- toYaml $cm.data | nindent 4 }}
    {{- else }}
    {}
    {{- end }}
    {{- else }}
    {}
    {{- end }}
{{- end }}

{{/* Validate cross-field chart contracts. */}}
{{- define "multica.validate" -}}
{{- if and .Values.postgres.enabled .Values.database.external.enabled -}}
{{- fail "multica: postgres.enabled and database.external.enabled cannot both be true" -}}
{{- end -}}
{{- if and (not .Values.postgres.enabled) (not .Values.database.external.enabled) -}}
{{- fail "multica: enable postgres or database.external" -}}
{{- end -}}
{{- if and .Values.database.external.enabled (not .Values.database.external.url) (not .Values.database.external.urlFrom.secretKeyRef.name) (not .Values.database.external.host) -}}
{{- fail "multica: database.external.host, database.external.url, or database.external.urlFrom.secretKeyRef.name is required when database.external.enabled=true" -}}
{{- end -}}
{{- if and .Values.database.waitForReady.enabled .Values.database.external.enabled (not .Values.database.external.host) (not .Values.database.external.url) -}}
{{- fail "multica: database.external.host or database.external.url is required when database.waitForReady.enabled=true and database.external.enabled=true" -}}
{{- end -}}
{{- if and .Values.database.external.enabled (not .Values.database.external.url) (not .Values.database.external.urlFrom.secretKeyRef.name) (or (not .Values.database.external.username) (not .Values.database.external.password)) -}}
{{- fail "multica: database.external.username and database.external.password are required when generating DATABASE_URL" -}}
{{- end -}}
{{- if and .Values.realtime.redisUrl .Values.realtime.redisUrlRef.name -}}
{{- fail "multica: realtime.redisUrl and realtime.redisUrlRef.name cannot both be set" -}}
{{- end -}}
{{- if and .Values.realtime.redisUrlRef.name (not .Values.realtime.redisUrlRef.key) -}}
{{- fail "multica: realtime.redisUrlRef.key is required when realtime.redisUrlRef.name is set" -}}
{{- end -}}
{{- if and .Values.backend.github.appSlug (not (or .Values.backend.github.webhookSecret .Values.backend.github.webhookSecretRef.name)) -}}
{{- fail "multica: backend.github.webhookSecret or backend.github.webhookSecretRef.name is required when backend.github.appSlug is set" -}}
{{- end -}}
{{- if and (or .Values.backend.github.webhookSecret .Values.backend.github.webhookSecretRef.name) (not .Values.backend.github.appSlug) -}}
{{- fail "multica: backend.github.appSlug is required when backend.github.webhookSecret or backend.github.webhookSecretRef.name is set" -}}
{{- end -}}
{{- if and .Values.backend.github.webhookSecretRef.name (not .Values.backend.github.webhookSecretRef.key) -}}
{{- fail "multica: backend.github.webhookSecretRef.key is required when backend.github.webhookSecretRef.name is set" -}}
{{- end -}}
{{- if and .Values.backend.github.appId (not (or .Values.backend.github.appPrivateKey .Values.backend.github.appPrivateKeyRef.name)) -}}
{{- fail "multica: backend.github.appPrivateKey or backend.github.appPrivateKeyRef.name is required when backend.github.appId is set" -}}
{{- end -}}
{{- if and (or .Values.backend.github.appPrivateKey .Values.backend.github.appPrivateKeyRef.name) (not .Values.backend.github.appId) -}}
{{- fail "multica: backend.github.appId is required when backend.github.appPrivateKey or backend.github.appPrivateKeyRef.name is set" -}}
{{- end -}}
{{- if and .Values.backend.github.appPrivateKeyRef.name (not .Values.backend.github.appPrivateKeyRef.key) -}}
{{- fail "multica: backend.github.appPrivateKeyRef.key is required when backend.github.appPrivateKeyRef.name is set" -}}
{{- end -}}
{{- if and .Values.backend.email.smtp.host .Values.backend.email.smtp.usernameRef.name (not .Values.backend.email.smtp.usernameRef.key) -}}
{{- fail "multica: backend.email.smtp.usernameRef.key is required when backend.email.smtp.usernameRef.name is set" -}}
{{- end -}}
{{- if and .Values.backend.email.smtp.host .Values.backend.email.smtp.passwordRef.name (not .Values.backend.email.smtp.passwordRef.key) -}}
{{- fail "multica: backend.email.smtp.passwordRef.key is required when backend.email.smtp.passwordRef.name is set" -}}
{{- end -}}
{{- if and .Values.backend.lark.secretKeyRef.name (not .Values.backend.lark.secretKeyRef.key) -}}
{{- fail "multica: backend.lark.secretKeyRef.key is required when backend.lark.secretKeyRef.name is set" -}}
{{- end -}}
{{- if and .Values.backend.slack.secretKeyRef.name (not .Values.backend.slack.secretKeyRef.key) -}}
{{- fail "multica: backend.slack.secretKeyRef.key is required when backend.slack.secretKeyRef.name is set" -}}
{{- end -}}
{{- if and .Values.backend.featureFlags.rules .Values.backend.featureFlags.existingConfigMap.name -}}
{{- fail "multica: backend.featureFlags.rules and backend.featureFlags.existingConfigMap.name cannot both be set" -}}
{{- end -}}
{{- if and .Values.backend.featureFlags.existingConfigMap.name (not .Values.backend.featureFlags.existingConfigMap.key) -}}
{{- fail "multica: backend.featureFlags.existingConfigMap.key is required when backend.featureFlags.existingConfigMap.name is set" -}}
{{- end -}}
{{- if and (or .Values.backend.featureFlags.rules .Values.backend.featureFlags.existingConfigMap.name) (not .Values.backend.featureFlags.mountPath) -}}
{{- fail "multica: backend.featureFlags.mountPath is required when feature flags are configured" -}}
{{- end -}}
{{- if and .Values.redis.enabled (not .Values.realtime.redisUrl) (not .Values.realtime.redisUrlRef.name) .Values.redis.auth.enabled (or .Values.redis.auth.existingSecret .Values.redis.auth.acl.enabled) -}}
{{- fail "multica: realtime.redisUrl or realtime.redisUrlRef is required when redis.enabled=true with redis.auth.existingSecret or redis.auth.acl.enabled" -}}
{{- end -}}
{{- if and .Values.httpRoute.enabled (eq (len .Values.httpRoute.parentRefs) 0) -}}
{{- fail "multica: httpRoute.parentRefs is required when httpRoute.enabled=true" -}}
{{- end -}}
{{- if and .Values.storage.local.persistence.enabled (gt (int .Values.backend.replicaCount) 1) (not .Values.storage.s3.bucket) -}}
{{- fail "multica: backend.replicaCount > 1 requires S3 storage or disabling local upload persistence" -}}
{{- end -}}
{{- if and .Values.backend.autoscaling.enabled .Values.storage.local.persistence.enabled (not .Values.storage.s3.bucket) -}}
{{- fail "multica: backend autoscaling requires S3 storage or disabling local upload persistence" -}}
{{- end -}}
{{- end }}
