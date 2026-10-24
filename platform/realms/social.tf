# 소셜 로그인 (Identity Provider) — var.social 에 값이 있는 것만 만든다
#   google : Google Cloud Console → OAuth 클라이언트
#   github : GitHub → Settings → Developer settings → OAuth Apps
#   kakao  : Kakao Developers → 카카오 로그인 (OpenID Connect 활성화)
#   naver  : OIDC 미지원 → Keycloak 확장(jar)이 필요해서 보류
#   각 서비스에 등록할 redirect URI: https://auth.claudharmony.io/realms/<realm>/broker/<alias>/endpoint
#
#   지금은 prd·dev realm 모두에 같은 앱을 붙인다 (서비스 콘솔에 redirect URI 두 개 등록)

locals {
  social_pairs = merge([
    for env, r in var.realms : {
      for name, cred in nonsensitive(var.social) : "${env}-${name}" => { env = env, name = name }
    }
  ]...)
}

resource "keycloak_oidc_google_identity_provider" "google" {
  for_each = { for k, v in local.social_pairs : k => v if v.name == "google" }

  realm          = keycloak_realm.this[each.value.env].id
  client_id      = var.social["google"].client_id
  client_secret  = var.social["google"].client_secret
  trust_email    = true
  sync_mode      = "IMPORT"
  default_scopes = "openid profile email"
}

resource "keycloak_oidc_identity_provider" "github" {
  for_each = { for k, v in local.social_pairs : k => v if v.name == "github" }

  realm             = keycloak_realm.this[each.value.env].id
  alias             = "github"
  provider_id       = "github"
  display_name      = "GitHub"
  client_id         = var.social["github"].client_id
  client_secret     = var.social["github"].client_secret
  authorization_url = "https://github.com/login/oauth/authorize"
  token_url         = "https://github.com/login/oauth/access_token"
  trust_email       = true
  sync_mode         = "IMPORT"
  default_scopes    = "user:email"
}

resource "keycloak_oidc_identity_provider" "kakao" {
  for_each = { for k, v in local.social_pairs : k => v if v.name == "kakao" }

  realm              = keycloak_realm.this[each.value.env].id
  alias              = "kakao"
  display_name       = "카카오"
  client_id          = var.social["kakao"].client_id
  client_secret      = var.social["kakao"].client_secret
  issuer             = "https://kauth.kakao.com"
  authorization_url  = "https://kauth.kakao.com/oauth/authorize"
  token_url          = "https://kauth.kakao.com/oauth/token"
  jwks_url           = "https://kauth.kakao.com/.well-known/jwks.json"
  user_info_url      = "https://kapi.kakao.com/v1/oidc/userinfo"
  validate_signature = true
  extra_config       = { clientAuthMethod = "client_secret_post" }
  sync_mode          = "IMPORT"
  default_scopes     = "openid profile_nickname account_email"
}
