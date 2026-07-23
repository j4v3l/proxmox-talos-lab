locals {
  gateway_api_manifest_url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"

  argocd_oidc_config = yamlencode({
    name         = "Authentik"
    issuer       = var.argocd_oidc_issuer
    clientID     = var.argocd_oidc_client_id
    clientSecret = "$oidc.authentik.clientSecret"
    requestedScopes = [
      "openid",
      "profile",
      "email",
      "groups",
    ]
  })
}
