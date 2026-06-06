{{- define "codex-pooler.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "codex-pooler.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s" (include "codex-pooler.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "codex-pooler.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "codex-pooler.labels" -}}
helm.sh/chart: {{ include "codex-pooler.chart" . }}
app.kubernetes.io/name: {{ include "codex-pooler.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "codex-pooler.selectorLabels" -}}
app.kubernetes.io/name: {{ include "codex-pooler.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "codex-pooler.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "codex-pooler.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "codex-pooler.secretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
{{- printf "%s-secrets" (include "codex-pooler.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "codex-pooler.validatedUpstreamSecretKey" -}}
{{- $key := required "secrets.upstreamSecretKey is required when secrets.create=true" .Values.secrets.upstreamSecretKey -}}
{{- $base64KeyPattern := "^(?:[A-Za-z0-9+/]{4}){10}(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)$" -}}
{{- $validBase64Key := and (regexMatch $base64KeyPattern $key) (eq (len (b64dec $key)) 32) -}}
{{- if and (ne (len $key) 32) (not $validBase64Key) -}}
{{- fail "secrets.upstreamSecretKey (CODEX_POOLER_UPSTREAM_SECRET_KEY) must be 32 raw bytes or base64-encoded 32 bytes when secrets.create=true" -}}
{{- end -}}
{{- $key -}}
{{- end -}}

{{- define "codex-pooler.clusteringHeadlessServiceName" -}}
{{- if .Values.clustering.headlessService.nameOverride -}}
{{- .Values.clustering.headlessService.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-cluster" (include "codex-pooler.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "codex-pooler.clusteringQuery" -}}
{{- if .Values.clustering.query -}}
{{- .Values.clustering.query -}}
{{- else -}}
{{- printf "%s.%s.svc.cluster.local" (include "codex-pooler.clusteringHeadlessServiceName" .) .Release.Namespace -}}
{{- end -}}
{{- end -}}

{{- define "codex-pooler.clusteringCookieSecretName" -}}
{{- if .Values.clustering.cookie.existingSecret -}}
{{- .Values.clustering.cookie.existingSecret -}}
{{- else -}}
{{- include "codex-pooler.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "codex-pooler.clusteringMemberLabel" -}}
codex-pooler.icoretech.io/cluster-member: "true"
{{- end -}}

{{- define "codex-pooler.clusteringEnv" -}}
{{- $root := .root -}}
{{- $role := .role -}}
{{- $participants := $root.Values.clustering.participants -}}
{{- $participates := false -}}
{{- if eq $role "app" -}}
{{- $participates = $participants.app -}}
{{- else if eq $role "worker" -}}
{{- $participates = $participants.worker -}}
{{- else if eq $role "scheduler" -}}
{{- $participates = $participants.scheduler -}}
{{- end -}}
{{- if and $root.Values.clustering.enabled $participates }}
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
- name: POD_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: DNS_CLUSTER_QUERY
  value: {{ include "codex-pooler.clusteringQuery" $root | quote }}
- name: RELEASE_DISTRIBUTION
  value: name
- name: RELEASE_NODE
  value: "codex_pooler@$(POD_IP)"
- name: RELEASE_COOKIE
  valueFrom:
    secretKeyRef:
      name: {{ include "codex-pooler.clusteringCookieSecretName" $root }}
      key: {{ required "clustering.cookie.existingSecretKey is required when clustering.enabled=true" $root.Values.clustering.cookie.existingSecretKey | quote }}
- name: ERL_AFLAGS
  value: {{ printf "-kernel inet_dist_listen_min %s inet_dist_listen_max %s" ($root.Values.clustering.distributionPort | toString) ($root.Values.clustering.distributionPort | toString) | quote }}
{{- end }}
{{- end -}}

{{- define "codex-pooler.websocketOwnerForwardingEnabled" -}}
{{- if .Values.app.websocketContinuity.ownerForwarding.enabled -}}true{{- end -}}
{{- end -}}

{{- define "codex-pooler.validateWebsocketTopology" -}}
{{- $ownerForwardingEnabled := eq (include "codex-pooler.websocketOwnerForwardingEnabled" .) "true" -}}
{{- if and $ownerForwardingEnabled (not .Values.clustering.enabled) -}}
{{- fail "app.websocketContinuity.ownerForwarding.enabled requires clustering.enabled=true so websocket owner pods can be reached across app nodes" -}}
{{- end -}}
{{- if and $ownerForwardingEnabled (not .Values.clustering.participants.app) -}}
{{- fail "app.websocketContinuity.ownerForwarding.enabled requires clustering.participants.app=true; worker or scheduler clustering cannot satisfy websocket owner forwarding" -}}
{{- end -}}
{{- if and .Values.app.enabled (gt (int .Values.app.replicaCount) 1) (not .Values.app.websocketContinuity.allowUnsafeMultiReplica) -}}
{{- fail "app.replicaCount > 1 is unsafe for backend websocket continuity until post-smoke guard relaxation is completed; set app.websocketContinuity.allowUnsafeMultiReplica=true only if external sticky routing and the documented reconnect limitations are acceptable" -}}
{{- end -}}
{{- end -}}

{{- define "codex-pooler.websocketOwnerForwardingEnv" -}}
{{- if eq (include "codex-pooler.websocketOwnerForwardingEnabled" .) "true" }}
- name: CODEX_POOLER_WEBSOCKET_OWNER_FORWARDING
  value: "true"
{{- end }}
{{- end -}}

{{- define "codex-pooler.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}

{{- define "codex-pooler.env" -}}
- name: PORT
  value: {{ .Values.config.port | quote }}
- name: PHX_HOST
  value: {{ .Values.config.host | quote }}
- name: POOL_SIZE
  value: {{ .Values.config.poolSize | quote }}
- name: ECTO_IPV6
  value: {{ .Values.config.ectoIpv6 | quote }}
- name: OBAN_JOBS_QUEUE_LIMIT
  value: {{ .Values.config.obanJobsQueueLimit | quote }}
- name: OBAN_SHUTDOWN_GRACE_PERIOD_MS
  value: {{ .Values.config.obanShutdownGracePeriodMs | quote }}
- name: LANG
  value: {{ .Values.config.lang | quote }}
- name: LC_ALL
  value: {{ .Values.config.lcAll | quote }}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ include "codex-pooler.secretName" . }}
      key: database-url
- name: SECRET_KEY_BASE
  valueFrom:
    secretKeyRef:
      name: {{ include "codex-pooler.secretName" . }}
      key: secret-key-base
- name: CODEX_POOLER_TOTP_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "codex-pooler.secretName" . }}
      key: totp-encryption-key
- name: CODEX_POOLER_TOTP_KEY_VERSION
  valueFrom:
    secretKeyRef:
      name: {{ include "codex-pooler.secretName" . }}
      key: totp-key-version
- name: CODEX_POOLER_UPSTREAM_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "codex-pooler.secretName" . }}
      key: upstream-secret-key
- name: CODEX_POOLER_UPSTREAM_SECRET_KEY_VERSION
  valueFrom:
    secretKeyRef:
      name: {{ include "codex-pooler.secretName" . }}
      key: upstream-secret-key-version
{{- end -}}
