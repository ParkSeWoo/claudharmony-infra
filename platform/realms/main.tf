# Keycloak 설정 — realm · client · 역할 · 계정 (Keycloak Terraform provider)
#
#   realm   claudharmony (prd) / claudharmony-dev (dev)
#   client  web     — SvelteKit 로그인 (Authorization Code + PKCE, confidential)
#           api     — 토큰을 검증하는 쪽(Resource Server). 로그인 기능 없음, audience 이름으로만 쓴다
#           console — 관리자 콘솔 로그인 (prd realm, admin 역할만)
#   역할    user (가입하면 기본), admin
#   Secret  각 앱 Namespace 에 keycloak-<client> — 앱은 이 값만 환경변수로 받으면 된다 (docs/12-identity.md)

locals {
  # 환경 → 앱 Namespace (console 은 별도 Namespace)
  app_namespace = { prd = "prd", dev = "dev" }
}

resource "keycloak_realm" "this" {
  for_each = var.realms

  realm        = each.value.realm
  display_name = each.value.display_name
  enabled      = true
  login_theme  = each.value.login_theme

  login_with_email_allowed = true
  duplicate_emails_allowed = false
  registration_allowed     = false # 가입은 소셜 로그인 붙인 뒤 결정
  remember_me              = true
  ssl_required             = "external" # 인터넷(터널) 요청은 https 만

  access_token_lifespan    = "5m"
  sso_session_idle_timeout = "30m"
  sso_session_max_lifespan = "10h"

  internationalization {
    supported_locales = ["ko", "en"]
    default_locale    = "ko"
  }

  security_defenses {
    brute_force_detection {
      permanent_lockout                = false
      max_login_failures               = 10
      wait_increment_seconds           = 60
      max_failure_wait_seconds         = 900
      failure_reset_time_seconds       = 43200
      quick_login_check_milli_seconds  = 1000
      minimum_quick_login_wait_seconds = 60
    }
    headers {
      x_frame_options                     = "SAMEORIGIN"
      content_security_policy             = "frame-src 'self'; frame-ancestors 'self'; object-src 'none';"
      x_content_type_options              = "nosniff"
      x_robots_tag                        = "none"
      strict_transport_security           = "max-age=31536000; includeSubDomains"
      referrer_policy                     = "no-referrer"
      x_xss_protection                    = "1; mode=block"
      content_security_policy_report_only = ""
    }
  }

  password_policy = "length(10) and notUsername and notEmail"
}

# ── 역할 ──
resource "keycloak_role" "user" {
  for_each    = var.realms
  realm_id    = keycloak_realm.this[each.key].id
  name        = "user"
  description = "일반 사용자 (기본)"
}

resource "keycloak_role" "admin" {
  for_each    = var.realms
  realm_id    = keycloak_realm.this[each.key].id
  name        = "admin"
  description = "관리자 — console 로그인 가능"
}

resource "keycloak_default_roles" "this" {
  for_each      = var.realms
  realm_id      = keycloak_realm.this[each.key].id
  default_roles = ["offline_access", "uma_authorization", keycloak_role.user[each.key].name]
}

# ── client: api (토큰 받는 쪽) ──
resource "keycloak_openid_client" "api" {
  for_each = var.realms

  realm_id    = keycloak_realm.this[each.key].id
  client_id   = "api"
  name        = "claudharmony-api"
  enabled     = true
  access_type = "BEARER-ONLY"
}

# ── client: web (로그인 하는 쪽) ──
resource "keycloak_openid_client" "web" {
  for_each = var.realms

  realm_id    = keycloak_realm.this[each.key].id
  client_id   = "web"
  name        = "claudharmony-web"
  enabled     = true
  access_type = "CONFIDENTIAL" # 서버(SvelteKit)가 토큰을 교환하므로 비밀 사용

  standard_flow_enabled        = true
  direct_access_grants_enabled = false # 비밀번호를 앱이 직접 받지 않는다
  implicit_flow_enabled        = false
  pkce_code_challenge_method   = "S256"

  valid_redirect_uris             = [for u in each.value.web_urls : "${u}/*"]
  valid_post_logout_redirect_uris = [for u in each.value.web_urls : "${u}/*"]
  web_origins                     = each.value.web_urls
  root_url                        = each.value.web_urls[0]
}

# web 이 받은 access token 의 aud 에 "api" 를 넣는다 → api 는 aud=api 인 토큰만 받는다
resource "keycloak_openid_audience_protocol_mapper" "web_api" {
  for_each = var.realms

  realm_id                 = keycloak_realm.this[each.key].id
  client_id                = keycloak_openid_client.web[each.key].id
  name                     = "audience-api"
  included_client_audience = keycloak_openid_client.api[each.key].client_id
  add_to_access_token      = true
  add_to_id_token          = false
}

# ── client: console (관리자 콘솔) ──
locals {
  console_realms = { for k, v in var.realms : k => v if length(v.console_urls) > 0 }
}

resource "keycloak_openid_client" "console" {
  for_each = local.console_realms

  realm_id    = keycloak_realm.this[each.key].id
  client_id   = "console"
  name        = "claudharmony-console"
  enabled     = true
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  pkce_code_challenge_method   = "S256"

  valid_redirect_uris             = [for u in each.value.console_urls : "${u}/*"]
  valid_post_logout_redirect_uris = [for u in each.value.console_urls : "${u}/*"]
  web_origins                     = each.value.console_urls
  root_url                        = each.value.console_urls[0]
}

# ── 앱에 넘길 값 (Kubernetes Secret) ──
resource "kubernetes_secret_v1" "web" {
  for_each = var.realms

  metadata {
    name      = "keycloak-web"
    namespace = local.app_namespace[each.key]
    labels    = { "app.kubernetes.io/managed-by" = "terraform", "claudharmony.io/source" = "platform-realms" }
  }
  data = {
    issuer-uri    = "${var.public_base}/realms/${each.value.realm}"
    internal-uri  = "${var.internal_base}/realms/${each.value.realm}"
    client-id     = keycloak_openid_client.web[each.key].client_id
    client-secret = keycloak_openid_client.web[each.key].client_secret
  }
}

resource "kubernetes_secret_v1" "api" {
  for_each = var.realms

  metadata {
    name      = "keycloak-api"
    namespace = local.app_namespace[each.key]
    labels    = { "app.kubernetes.io/managed-by" = "terraform", "claudharmony.io/source" = "platform-realms" }
  }
  data = {
    issuer-uri  = "${var.public_base}/realms/${each.value.realm}"
    jwk-set-uri = "${var.internal_base}/realms/${each.value.realm}/protocol/openid-connect/certs"
    audience    = keycloak_openid_client.api[each.key].client_id
  }
}

resource "kubernetes_secret_v1" "console" {
  for_each = local.console_realms

  metadata {
    name      = "keycloak-console"
    namespace = "console"
    labels    = { "app.kubernetes.io/managed-by" = "terraform", "claudharmony.io/source" = "platform-realms" }
  }
  data = {
    issuer-uri    = "${var.public_base}/realms/${each.value.realm}"
    internal-uri  = "${var.internal_base}/realms/${each.value.realm}"
    client-id     = keycloak_openid_client.console[each.key].client_id
    client-secret = keycloak_openid_client.console[each.key].client_secret
  }
}

# ── 사람용 계정 ──
# master realm 관리자 (관리 콘솔 http://auth.localhost/admin/) — 비밀번호는 Secret identity/keycloak-admin
data "keycloak_realm" "master" {
  realm = "master"
}

data "keycloak_role" "master_admin" {
  realm_id = data.keycloak_realm.master.id
  name     = "admin"
}

resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "keycloak_user" "admin" {
  realm_id       = data.keycloak_realm.master.id
  username       = "claudharmony-admin"
  enabled        = true
  email_verified = true
  first_name     = "Cloud"
  last_name      = "Harmony"

  initial_password {
    value     = random_password.admin.result
    temporary = false
  }

  lifecycle {
    ignore_changes = [initial_password] # 콘솔에서 비밀번호를 바꿔도 되돌리지 않음
  }
}

resource "keycloak_user_roles" "admin" {
  realm_id = data.keycloak_realm.master.id
  user_id  = keycloak_user.admin.id
  role_ids = [data.keycloak_role.master_admin.id]
}

resource "kubernetes_secret_v1" "admin" {
  metadata {
    name      = "keycloak-admin"
    namespace = "identity"
  }
  data = {
    username = keycloak_user.admin.username
    password = random_password.admin.result
  }
}

# dev 로그인 확인용 사용자 — Secret dev/keycloak-tester
resource "random_password" "tester" {
  for_each = { for k, v in var.realms : k => v if v.test_user }
  length   = 16
  special  = false
}

resource "keycloak_user" "tester" {
  for_each = random_password.tester

  realm_id       = keycloak_realm.this[each.key].id
  username       = "tester"
  email          = "tester@dev.claudharmony.io"
  email_verified = true
  first_name     = "테스트"
  last_name      = "사용자"
  enabled        = true

  initial_password {
    value     = each.value.result
    temporary = false
  }
}

resource "kubernetes_secret_v1" "tester" {
  for_each = random_password.tester

  metadata {
    name      = "keycloak-tester"
    namespace = local.app_namespace[each.key]
  }
  data = {
    username = keycloak_user.tester[each.key].username
    password = each.value.result
  }
}

# ── master realm (관리용) 은 사무실 주소에서만 ──
# 서버 설정 KC_HOSTNAME 은 모든 realm 의 기본 주소(공개). master 만 Frontend URL 을 auth.localhost 로 덮어써서
# 관리자 로그인·토큰이 인터넷 주소를 거치지 않게 한다. (공개 HTTPRoute 는 /realms/master 를 막아 둠)
# master realm 전체를 Terraform 리소스로 가져오면 기본값으로 덮어쓸 위험이 있어 이 속성 하나만 REST 로 맞춘다.
resource "terraform_data" "master_frontend_url" {
  input = var.master_frontend_url

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-SH
      set -euo pipefail
      TOKEN="$(curl -sf -d grant_type=client_credentials -d client_id=terraform-bootstrap --data-urlencode client_secret="$KC_SECRET" \
        "$KC_URL/realms/master/protocol/openid-connect/token" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')"
      curl -sf -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
        -d "{\"attributes\":{\"frontendUrl\":\"$FRONTEND\"}}" "$KC_URL/admin/realms/master"
      echo "master frontendUrl = $FRONTEND"
    SH
    environment = {
      KC_URL    = var.keycloak_url
      KC_SECRET = var.keycloak_client_secret
      FRONTEND  = var.master_frontend_url
    }
  }
}
