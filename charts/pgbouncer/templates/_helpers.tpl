{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "pgbouncer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pgbouncer.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pgbouncer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create content for userlist.txt secret
*/}}
{{- define "pgbouncer.secret.userlist" }}
{{- if not .Values.config.existingAdminSecret -}}
"{{ .Values.config.adminUser }}" "{{ required "A valid .Values.config.adminPassword entry required!" .Values.config.adminPassword }}"
{{- end }}
{{- if .Values.config.authUser }}
"{{ .Values.config.authUser }}" "{{ required "A valid .Values.config.authPassword entry required!" .Values.config.authPassword }}"
{{- end }}
{{- range $key, $val := .Values.config.userlist }}
"{{ $key }}" "{{ $val }}"
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "pgbouncer.serviceAccountName" -}}
{{- if not .Values.serviceAccount.name -}}
{{ template "pgbouncer.fullname" . }}
{{- else -}}
{{- .Values.serviceAccount.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Contruct and return the image to use
*/}}
{{- define "pgbouncer.image" -}}
{{- if not .Values.image.registry -}}
{{ printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- else -}}
{{ printf "%s/%s:%s" .Values.image.registry .Values.image.repository .Values.image.tag }}
{{- end -}}
{{- end -}}

{{/*
Contruct and return the exporter image to use
*/}}
{{- define "pgbouncer.exporterImage" -}}
{{- if not .Values.pgbouncerExporter.image.registry -}}
{{ printf "%s:%s" .Values.pgbouncerExporter.image.repository .Values.pgbouncerExporter.image.tag }}
{{- else -}}
{{ printf "%s/%s:%s" .Values.pgbouncerExporter.image.registry .Values.pgbouncerExporter.image.repository .Values.pgbouncerExporter.image.tag }}
{{- end -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "pgbouncer.labels" -}}
helm.sh/chart: {{ include "pgbouncer.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/name: {{ include "pgbouncer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "pgbouncer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pgbouncer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Return the appropriate apiVersion for deployment.
*/}}
{{- define "deployment.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "apps/v1/Deployment" -}}
{{- print "apps/v1" -}}
{{- else -}}
{{- print "extensions/v1beta1" -}}
{{- end -}}
{{- end -}}

{{/*
Return the appropriate apiVersion for PodDisruptionBudget kind of objects.
*/}}
{{- define "podDisruptionBudget.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "policy/v1/PodDisruptionBudget" -}}
{{- print "policy/v1" -}}
{{- else -}}
{{- if .Capabilities.APIVersions.Has "policy/v1beta1/PodDisruptionBudget" -}}
{{- print "policy/v1beta1" -}}
{{- else -}}
{{- print "extensions/v1beta1" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return the appropriate apiVersion for Role kind of objects.
*/}}
{{- define "role.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "rbac.authorization.k8s.io/v1/Role" -}}
{{- print "rbac.authorization.k8s.io/v1" -}}
{{- else -}}
{{- if .Capabilities.APIVersions.Has "rbac.authorization.k8s.io/v1beta1/Role" -}}
{{- print "rbac.authorization.k8s.io/v1beta1" -}}
{{- else -}}
{{- print "rbac.authorization.k8s.io/v1alpha1" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return the appropriate apiVersion for RoleBinding kind of objects.
*/}}
{{- define "roleBinding.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "rbac.authorization.k8s.io/v1/RoleBinding" -}}
{{- print "rbac.authorization.k8s.io/v1" -}}
{{- else -}}
{{- if .Capabilities.APIVersions.Has "rbac.authorization.k8s.io/v1beta1/RoleBinding" -}}
{{- print "rbac.authorization.k8s.io/v1beta1" -}}
{{- else -}}
{{- print "rbac.authorization.k8s.io/v1alpha1" -}}
{{- end -}}
{{- end -}}
{{- end -}}
