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

{{- define "codex-pooler.runtimePodAnnotations" -}}
{{- $root := .root -}}
{{- $rolePodAnnotations := default (dict) .podAnnotations -}}
{{- $annotations := mergeOverwrite (dict) (default (dict) $root.Values.podAnnotations) $rolePodAnnotations -}}
{{- with $annotations -}}
annotations:
{{- toYaml . | nindent 2 }}
{{- end -}}
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

{{/*
The Secret the migration hook reads.

`migration-job.yaml` is a pre-install/pre-upgrade hook, and hooks run before the
release manifests are applied. When the chart creates the Secret itself, that
Secret is a manifest and does not exist yet when the hook starts, so the hook
gets its own copy: same data, created earlier in the same hook phase, removed
again when the phase succeeds. When the operator supplies `secrets.existingSecret`,
that Secret already exists and the hook reads it directly.
*/}}
{{- define "codex-pooler.migrationsSecretName" -}}
{{- if .Values.secrets.create -}}
{{- printf "%s-migrations" (include "codex-pooler.secretName" .) | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "codex-pooler.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "codex-pooler.secretData" -}}
database-url: {{ required "secrets.databaseUrl is required when secrets.create=true" .Values.secrets.databaseUrl | quote }}
secret-key-base: {{ required "secrets.secretKeyBase is required when secrets.create=true" .Values.secrets.secretKeyBase | quote }}
totp-encryption-key: {{ required "secrets.totpEncryptionKey is required when secrets.create=true" .Values.secrets.totpEncryptionKey | quote }}
totp-key-version: {{ .Values.secrets.totpKeyVersion | quote }}
upstream-secret-key: {{ include "codex-pooler.validatedUpstreamSecretKey" . | quote }}
upstream-secret-key-version: {{ .Values.secrets.upstreamSecretKeyVersion | quote }}
{{- if and .Values.clustering.enabled (not .Values.clustering.cookie.existingSecret) .Values.clustering.cookie.value }}
{{ .Values.clustering.cookie.existingSecretKey }}: {{ .Values.clustering.cookie.value | quote }}
{{- end }}
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

{{- define "codex-pooler.appLocalRpcEnv" -}}
{{- if not (and .Values.clustering.enabled .Values.clustering.participants.app) }}
- name: RELEASE_DISTRIBUTION
  value: sname
- name: RELEASE_NODE
  value: codex_pooler
{{- end }}
{{- end -}}

{{- define "codex-pooler.appReplicaCountAtLeastTwo" -}}
{{- if and .Values.app.enabled (ge (int .Values.app.replicaCount) 2) -}}true{{- end -}}
{{- end -}}

{{- define "codex-pooler.explicitWebsocketOwnerForwardingEnabled" -}}
{{- with .Values.app.websocketContinuity -}}
{{- with .ownerForwarding -}}
{{- if .enabled -}}true{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "codex-pooler.websocketOwnerForwardingEnabled" -}}
{{- if or (eq (include "codex-pooler.appReplicaCountAtLeastTwo" .) "true") (eq (include "codex-pooler.explicitWebsocketOwnerForwardingEnabled" .) "true") -}}true{{- end -}}
{{- end -}}

{{- define "codex-pooler.validateWebsocketTopology" -}}
{{- $ownerForwardingEnabled := eq (include "codex-pooler.websocketOwnerForwardingEnabled" .) "true" -}}
{{- if and $ownerForwardingEnabled (not .Values.clustering.enabled) -}}
{{- fail "websocket owner forwarding requires clustering.enabled=true so websocket owner pods can be reached across app nodes" -}}
{{- end -}}
{{- if and $ownerForwardingEnabled (not .Values.clustering.participants.app) -}}
{{- fail "websocket owner forwarding requires clustering.participants.app=true; worker or scheduler clustering cannot satisfy websocket owner forwarding" -}}
{{- end -}}
{{- end -}}

{{- define "codex-pooler.validateAppLifecycleBudget" -}}
{{- if and .Values.app.enabled .Values.app.lifecycle.preStop.enabled -}}
{{- $drainTimeoutSeconds := int .Values.app.lifecycle.preStop.drainTimeoutSeconds -}}
{{- $sleepSeconds := int .Values.app.lifecycle.preStop.sleepSeconds -}}
{{- $terminationGracePeriodSeconds := int .Values.app.terminationGracePeriodSeconds -}}
{{- $rpcTimeoutAllowanceSeconds := 2 -}}
{{- $endpointShutdownSeconds := 10 -}}
{{- $shutdownMarginSeconds := 5 -}}
{{- $preStopSeconds := add (add $drainTimeoutSeconds $rpcTimeoutAllowanceSeconds) $sleepSeconds -}}
{{- $inVmFallbackSeconds := add (add $rpcTimeoutAllowanceSeconds $sleepSeconds) $drainTimeoutSeconds -}}
{{- $drainAndSleepSeconds := max $preStopSeconds $inVmFallbackSeconds -}}
{{- $requiredGraceSeconds := add (add $drainAndSleepSeconds $endpointShutdownSeconds) $shutdownMarginSeconds -}}
{{- if lt $terminationGracePeriodSeconds $requiredGraceSeconds -}}
{{- fail (printf "invalid app lifecycle preStop budget: terminationGracePeriodSeconds (%d) must be >= max(drainTimeoutSeconds (%d) + 2 + sleepSeconds (%d), 2 + sleepSeconds (%d) + drainTimeoutSeconds (%d)) + 10 endpoint shutdown + 5 margin = %d" $terminationGracePeriodSeconds $drainTimeoutSeconds $sleepSeconds $sleepSeconds $drainTimeoutSeconds $requiredGraceSeconds) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "codex-pooler.websocketOwnerForwardingEnv" -}}
{{- if eq (include "codex-pooler.websocketOwnerForwardingEnabled" .) "true" }}
- name: CODEX_POOLER_WEBSOCKET_OWNER_FORWARDING
  value: "true"
{{- end }}
{{- end -}}

{{- define "codex-pooler.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) -}}
{{- end -}}

{{- define "codex-pooler.env" -}}
{{- $root := default . .root -}}
{{- $secretName := default (include "codex-pooler.secretName" $root) .secretName -}}
- name: PORT
  value: {{ $root.Values.config.port | quote }}
- name: PHX_HOST
  value: {{ $root.Values.config.host | quote }}
- name: POOL_SIZE
  value: {{ $root.Values.config.poolSize | quote }}
- name: ECTO_IPV6
  value: {{ $root.Values.config.ectoIpv6 | quote }}
- name: OBAN_JOBS_QUEUE_LIMIT
  value: {{ $root.Values.config.obanJobsQueueLimit | quote }}
- name: OBAN_SHUTDOWN_GRACE_PERIOD_MS
  value: {{ $root.Values.config.obanShutdownGracePeriodMs | quote }}
- name: LANG
  value: {{ $root.Values.config.lang | quote }}
- name: LC_ALL
  value: {{ $root.Values.config.lcAll | quote }}
- name: ERL_MAX_PORTS
  value: {{ $root.Values.config.erlMaxPorts | quote }}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: database-url
- name: SECRET_KEY_BASE
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: secret-key-base
- name: CODEX_POOLER_TOTP_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: totp-encryption-key
- name: CODEX_POOLER_TOTP_KEY_VERSION
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: totp-key-version
- name: CODEX_POOLER_UPSTREAM_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: upstream-secret-key
- name: CODEX_POOLER_UPSTREAM_SECRET_KEY_VERSION
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: upstream-secret-key-version
{{- end -}}
