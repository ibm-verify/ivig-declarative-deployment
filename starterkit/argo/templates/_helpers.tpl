{{/*
Dictionary entries of files matching a pattern within the certificate directory
Usage: include "certs" (list . "{mq.key,mq.crt,isvgimRootCA.crt}")
*/}}
{{- define "certs" }}
  {{- $ := index . 0 }}
  {{- $glob := index . 1 }}
  {{- ($.Files.Glob (print (default "config/certs" $.Values.general.install.certDir) "/" $glob) ).AsConfig | indent 2 }}
{{- end }}
