{{/*
Shortcut to construct a glob pattern within the certificate directory
Usage: include "certs" (list . "{mq.key,mq.crt,isvgimRootCA.crt}")
*/}}
{{- define "certs" }}
  {{- $ := index . 0 }}
  {{- $glob := index . 1 }}
  {{- print (default "config/certs" $.Values.general.install.certDir) "/" $glob }}
{{- end }}
