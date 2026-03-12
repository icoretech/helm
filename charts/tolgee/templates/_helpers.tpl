{{/* Expand the name of the chart. */}}
{{- define "tolgee.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully-qualified app name. */}}
{{- define "tolgee.fullname" -}}
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
{{- define "tolgee.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels. */}}
{{- define "tolgee.labels" -}}
helm.sh/chart: {{ include "tolgee.chart" . }}
{{ include "tolgee.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Selector labels. */}}
{{- define "tolgee.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tolgee.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Service account name. */}}
{{- define "tolgee.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "tolgee.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* PVC name. */}}
{{- define "tolgee.persistence.claimName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim -}}
{{- else -}}
{{- printf "%s-data" (include "tolgee.fullname" .) -}}
{{- end -}}
{{- end }}

{{/* Dot/hyphen property key to ENV VAR name. */}}
{{- define "tolgee.propertyToEnvName" -}}
{{- . | replace "." "_" | replace "-" "_" | upper -}}
{{- end }}

{{/* Default service name of the internal Postgres dependency. */}}
{{- define "tolgee.postgres.serviceName" -}}
{{- if .Values.database.internal.serviceName -}}
{{- .Values.database.internal.serviceName -}}
{{- else -}}
{{- printf "%s-postgres" .Release.Name -}}
{{- end -}}
{{- end }}

{{/* JDBC query string suffix. */}}
{{- define "tolgee.database.queryString" -}}
{{- $parts := list -}}
{{- if .Values.database.sslMode -}}
{{- $parts = append $parts (printf "sslmode=%s" .Values.database.sslMode) -}}
{{- end -}}
{{- if .Values.database.jdbcParameters -}}
{{- $parts = append $parts (trimPrefix "?" .Values.database.jdbcParameters) -}}
{{- end -}}
{{- if gt (len $parts) 0 -}}
?{{ join "&" $parts }}
{{- end -}}
{{- end }}

{{/* SPRING_DATASOURCE_URL resolved for internal/external mode. */}}
{{- define "tolgee.database.jdbcUrl" -}}
{{- if .Values.database.external.enabled -}}
  {{- if .Values.database.external.jdbcUrl -}}
    {{- .Values.database.external.jdbcUrl -}}
  {{- else -}}
    {{- printf "jdbc:postgresql://%s:%v/%s%s" .Values.database.external.host .Values.database.external.port .Values.database.external.name (include "tolgee.database.queryString" .) -}}
  {{- end -}}
{{- else -}}
  {{- printf "jdbc:postgresql://%s:%v/%s%s" (include "tolgee.postgres.serviceName" .) .Values.database.internal.port (default "postgres" .Values.postgres.auth.database) (include "tolgee.database.queryString" .) -}}
{{- end -}}
{{- end }}

{{/* Database host resolved for internal/external mode. */}}
{{- define "tolgee.database.host" -}}
{{- if .Values.database.external.enabled -}}
  {{- .Values.database.external.host -}}
{{- else -}}
  {{- include "tolgee.postgres.serviceName" . -}}
{{- end -}}
{{- end }}

{{/* Database port resolved for internal/external mode. */}}
{{- define "tolgee.database.port" -}}
{{- if .Values.database.external.enabled -}}
  {{- .Values.database.external.port -}}
{{- else -}}
  {{- .Values.database.internal.port -}}
{{- end -}}
{{- end }}

{{/* SPRING_DATASOURCE_USERNAME resolved for internal/external mode. */}}
{{- define "tolgee.database.username" -}}
{{- if .Values.database.external.enabled -}}
  {{- .Values.database.external.username -}}
{{- else -}}
  {{- default "postgres" .Values.postgres.auth.username -}}
{{- end -}}
{{- end }}

{{/* SPRING_DATASOURCE_PASSWORD resolved for internal/external mode. */}}
{{- define "tolgee.database.password" -}}
{{- if .Values.database.external.enabled -}}
  {{- .Values.database.external.password -}}
{{- else -}}
  {{- default "" .Values.postgres.auth.password -}}
{{- end -}}
{{- end }}
