# 소셜 로그인 (Identity Provider) — var.social 에 값이 있는 것만 만든다
#   google : Google Cloud Console → OAuth 클라이언트
#   naver  : 네이버 개발자센터 → 애플리케이션 등록 (네이버 로그인)
#   github : GitHub → Settings → Developer settings → OAuth Apps
#   kakao  : Kakao Developers → 카카오 로그인 (OpenID Connect 활성화)
#   naver  : OIDC 미지원 → Keycloak 기본 OAuth 2.0 공급자(provider_id "oauth2")로. 사용자 정보는 response.* 아래에 있다
#            alias 는 "naver" 고정 — 로그인 테마(claudharmony-keycloak)가 alias 로 버튼 색을 입힌다
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

resource "keycloak_oidc_github_identity_provider" "github" {
  for_each = { for k, v in local.social_pairs : k => v if v.name == "github" }

  realm          = keycloak_realm.this[each.value.env].id
  client_id      = var.social["github"].client_id
  client_secret  = var.social["github"].client_secret
  trust_email    = true
  sync_mode      = "IMPORT"
  default_scopes = "user:email"
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

resource "keycloak_oidc_identity_provider" "naver" {
  for_each = { for k, v in local.social_pairs : k => v if v.name == "naver" }

  realm              = keycloak_realm.this[each.value.env].id
  alias              = "naver"
  provider_id        = "oauth2"
  display_name       = "네이버"
  client_id          = var.social["naver"].client_id
  client_secret      = var.social["naver"].client_secret
  authorization_url  = "https://nid.naver.com/oauth2.0/authorize"
  token_url          = "https://nid.naver.com/oauth2.0/token"
  user_info_url      = "https://openapi.naver.com/v1/nid/me"
  validate_signature = false # OIDC 가 아니라 ID 토큰·서명이 없다
  sync_mode          = "IMPORT"
  default_scopes     = ""
  extra_config = {
    clientAuthMethod = "client_secret_post"
    userIDClaim      = "response.id"
    userNameClaim    = "response.email"
    emailClaim       = "response.email"
    fullNameClaim    = "response.name"
  }
}
