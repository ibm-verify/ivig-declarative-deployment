{{/*
Copyright IBM Corp. 2026
SPDX-License-Identifier: MIT
*/}}

{{/*
Dictionary entries of files matching a pattern within the certificate directory
Usage: include "certs" (list . "{mq.key,mq.crt,isvgimRootCA.crt}")
*/}}
{{- define "certs" }}
  {{- $ := index . 0 }}
  {{- $glob := index . 1 }}
  {{- ($.Files.Glob (print (default "config/certs" $.Values.general.install.certDir) "/" $glob) ).AsConfig | indent 2 }}
{{- end }}

{{/*
Looks up and returns an object under .Values.extra based on a string which
represents a dot-separated path. The object found is either a string which will
be dynamically rendered as a template, or a yaml structure to be included as-is.
Optionally, one may pass a number to override the default indentation of 8.
Gracefully handles missing or invalid path.

Example use case: This named template may be used to add extra annotations or
labels to pod templates (within deployments, stateful sets) or services.
Usage: include "extra" (list . "annotations.pod.isvdi" 4)
*/}}
{{- define "extra" }}
  {{- $ := index . 0 }}
  {{- $n := lt 2 (len .) | ternary (last . ) 8 }}
  {{- $r := $.Values.extra }}
  {{- range index . 1 | split "." }}
    {{- $r = and (kindIs "map" $r) (hasKey $r .) | ternary (get $r .) nil }}
  {{- end }}
  {{- if kindIs "string" $r }}
    {{- tpl $r $ | nindent $n}}
  {{- else if $r }}
    {{- toYaml $r | nindent $n }}
  {{- end }}
{{- end }}
