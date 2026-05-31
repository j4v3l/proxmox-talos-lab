{{- define "talos-lab.sslipHost" -}}
{{ printf "%s.%s.sslip.io" .name .root.Values.ingressLoadBalancerIp }}
{{- end -}}

{{- define "talos-lab.labHost" -}}
{{ printf "%s.%s" .name .root.Values.labBaseDomain }}
{{- end -}}
