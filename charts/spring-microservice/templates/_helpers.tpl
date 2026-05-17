{{/*
Nome standard del servizio (usato per metadata.name, labels, selectors).
*/}}
{{- define "spring-microservice.name" -}}
{{- required "values.name è obbligatorio" .Values.name -}}
{{- end -}}

{{/*
Label comuni applicate a tutte le risorse generate dal chart.
*/}}
{{- define "spring-microservice.labels" -}}
app.kubernetes.io/name: {{ include "spring-microservice.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: argocd
app.kubernetes.io/part-of: ai-burraco
{{- end -}}

{{/*
Selector labels (subset di labels, immutabili dopo il primo apply).
*/}}
{{- define "spring-microservice.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spring-microservice.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
