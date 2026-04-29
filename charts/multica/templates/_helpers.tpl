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
