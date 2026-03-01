{{- define "metamcp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "metamcp.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "metamcp.labels" -}}
app.kubernetes.io/name: {{ include "metamcp.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "metamcp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "metamcp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "metamcp.postgresFullname" -}}
{{- printf "%s-postgres" (include "metamcp.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /* Compute APP_URL from values.env.APP_URL or fallback to Service FQDN */ -}}
{{- define "metamcp.appurl" -}}
{{- $env := (default (dict) .Values.env) -}}
{{- $default := printf "http://%s.%s.svc.cluster.local:%v" (include "metamcp.fullname" .) .Release.Namespace (.Values.service.port | int) -}}
{{- default $default (get $env "APP_URL") -}}
{{- end -}}
