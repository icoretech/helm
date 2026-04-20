{{/* Expand the name of the chart. */}}
{{- define "codex-lb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully-qualified app name. */}}
{{- define "codex-lb.fullname" -}}
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
{{- define "codex-lb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels. */}}
{{- define "codex-lb.labels" -}}
helm.sh/chart: {{ include "codex-lb.chart" . }}
{{ include "codex-lb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Selector labels. */}}
{{- define "codex-lb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "codex-lb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Service account name. */}}
{{- define "codex-lb.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "codex-lb.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Internal handoff headless service name for replicated mode. */}}
{{- define "codex-lb.handoffServiceName" -}}
{{- printf "%s-handoff" (include "codex-lb.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/* Replicated workload name. */}}
{{- define "codex-lb.replicatedWorkloadName" -}}
{{- printf "%s-replicated" (include "codex-lb.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/* Continuity route name. */}}
{{- define "codex-lb.continuityRouteName" -}}
{{- printf "%s-responses" (include "codex-lb.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/* Derived replicated-mode handoff advertise URL. */}}
{{- define "codex-lb.replication.handoffAdvertiseUrl" -}}
{{- if .Values.replication.handoffAdvertiseUrl -}}
{{- .Values.replication.handoffAdvertiseUrl -}}
{{- else -}}
{{- printf "http://$(POD_NAME).%s.$(POD_NAMESPACE).svc.%s:%v" (include "codex-lb.handoffServiceName" .) .Values.topology.clusterDomain .Values.service.targetPort -}}
{{- end -}}
{{- end }}

{{/* Gateway API path type for continuity rules. */}}
{{- define "codex-lb.httpRouteContinuityPathType" -}}
{{- if eq .Values.replication.continuity.pathType "Exact" -}}
Exact
{{- else -}}
PathPrefix
{{- end -}}
{{- end }}

{{/* PVC name. */}}
{{- define "codex-lb.persistence.claimName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim -}}
{{- else -}}
{{- printf "%s-data" (include "codex-lb.fullname" .) -}}
{{- end -}}
{{- end }}

{{/* Migration job name. */}}
{{- define "codex-lb.migrationJobName" -}}
{{- printf "%s-migrate" (include "codex-lb.fullname" . | trunc 55 | trimSuffix "-") -}}
{{- end }}
