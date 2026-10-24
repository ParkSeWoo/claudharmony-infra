# 인증 서버 — Keycloak (Namespace identity)
#   여러 로그인 방식(아이디/비밀번호, Google, GitHub ...)을 한곳에서 관리하고
#   web·api·console 은 OIDC 로 Keycloak 에 로그인을 맡긴다. (AWS Cognito, GCP Identity Platform 에 해당)
#
#   주소
#     https://auth.claudharmony.io  로그인·토큰 (공개: /realms/<공개 realm>, /resources 만)
#     http://auth.localhost          관리 콘솔 (사무실 Mac 전용, /admin 포함 전체)
#
#   이 스택은 서버만 띄운다. realm·client·사용자 설정은 platform/realms (Keycloak provider) 가 한다.

locals {
  # 커스텀 이미지(테마 포함)가 배포돼 있으면 그것, 없으면 공식 이미지
  image     = lookup(var.images, "keycloak", var.keycloak_image)
  namespace = "identity"
  labels    = { "app.kubernetes.io/name" = "keycloak", "app.kubernetes.io/part-of" = "claudharmony", "app.kubernetes.io/managed-by" = "terraform" }
}

resource "kubernetes_namespace_v1" "identity" {
  metadata {
    name   = local.namespace
    labels = { "claudharmony.io/gateway-access" = "true" }
  }
}

# Keycloak 전용 DB — 앱 DB 와 분리 (장애·백업·업그레이드 영향 범위를 나눈다)
module "db" {
  source = "../../modules/k8s/postgres"

  namespace    = kubernetes_namespace_v1.identity.metadata[0].name
  database     = "keycloak"
  extensions   = []
  storage_size = "2Gi"
  memory_mb    = 256
}

# 첫 기동 때만 쓰는 관리용 client (client_credentials) — Terraform(platform/realms)이 이걸로 설정한다.
# 사람용 관리자 계정은 platform/realms 가 만든다.
resource "random_password" "bootstrap" {
  length  = 40
  special = false
}

resource "kubernetes_secret_v1" "bootstrap" {
  metadata {
    name      = "keycloak-bootstrap"
    namespace = local.namespace
  }
  data = {
    client-id     = "terraform-bootstrap"
    client-secret = random_password.bootstrap.result
  }
}

resource "kubernetes_deployment_v1" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = local.namespace
    labels    = local.labels
  }

  # 세션은 DB·분산 캐시에 있지만 1대로 시작 (메모리 절약). 늘리면 Infinispan 이 Pod 끼리 캐시를 맞춘다.
  wait_for_rollout = true

  spec {
    replicas = 1
    selector {
      match_labels = { "app.kubernetes.io/name" = "keycloak" }
    }

    strategy {
      type = "Recreate" # 1대일 때 구버전·신버전이 동시에 DB 스키마를 건드리지 않게
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        container {
          name  = "keycloak"
          image = local.image
          # 커스텀 이미지는 같은 빌드 옵션(KC_DB 등)으로 kc.sh build 돼 있어 재빌드 없이 바로 뜬다
          args = ["start"]

          env {
            name  = "KC_DB"
            value = "postgres"
          }
          env {
            name  = "KC_DB_URL"
            value = module.db.jdbc_url
          }
          env {
            name = "KC_DB_USERNAME"
            value_from {
              secret_key_ref {
                name = module.db.app_secret
                key  = "username"
              }
            }
          }
          env {
            name = "KC_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = module.db.app_secret
                key  = "password"
              }
            }
          }

          # 주소 — 토큰 issuer 는 항상 공개 주소. 관리 콘솔만 별도 주소.
          env {
            name  = "KC_HOSTNAME"
            value = "https://${var.public_hostname}"
          }
          env {
            name  = "KC_HOSTNAME_ADMIN"
            value = "http://${var.admin_hostname}"
          }
          # 클러스터 안 앱이 http://keycloak.identity.svc 로 키(JWKS)를 받아갈 수 있게
          env {
            name  = "KC_HOSTNAME_BACKCHANNEL_DYNAMIC"
            value = "true"
          }
          # TLS 는 Cloudflare 가 끝낸다 → 안쪽은 http, 원래 주소는 X-Forwarded-* 헤더로 안다
          env {
            name  = "KC_HTTP_ENABLED"
            value = "true"
          }
          env {
            name  = "KC_PROXY_HEADERS"
            value = "xforwarded"
          }
          env {
            name  = "KC_HEALTH_ENABLED"
            value = "true"
          }
          env {
            name  = "KC_METRICS_ENABLED"
            value = "true"
          }
          env {
            name  = "KC_CACHE"
            value = "local" # 1대 운영. 여러 대로 늘릴 때 ispn(+ kubernetes stack)으로
          }
          env {
            name  = "TZ"
            value = "Asia/Seoul"
          }

          env {
            name = "KC_BOOTSTRAP_ADMIN_CLIENT_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.bootstrap.metadata[0].name
                key  = "client-id"
              }
            }
          }
          env {
            name = "KC_BOOTSTRAP_ADMIN_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.bootstrap.metadata[0].name
                key  = "client-secret"
              }
            }
          }

          port {
            name           = "http"
            container_port = 8080
          }
          port {
            name           = "management"
            container_port = 9000 # /health, /metrics — Gateway 에 연결하지 않음
          }

          resources {
            requests = { cpu = "100m", memory = "${floor(var.memory_mb * 3 / 4)}Mi" }
            limits   = { memory = "${var.memory_mb}Mi" }
          }

          # 첫 기동은 DB 스키마 생성 + 빌드 단계로 1~2분 걸린다
          startup_probe {
            http_get {
              path = "/health/started"
              port = "management"
            }
            period_seconds    = 5
            failure_threshold = 60
          }
          readiness_probe {
            http_get {
              path = "/health/ready"
              port = "management"
            }
            period_seconds = 10
          }
          liveness_probe {
            http_get {
              path = "/health/live"
              port = "management"
            }
            period_seconds    = 20
            failure_threshold = 6
          }
        }
      }
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
  }

  depends_on = [module.db] # DB 가 healthy 가 된 뒤 기동 (먼저 뜨면 접속 실패로 재시작)
}

resource "kubernetes_service_v1" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = local.namespace
    labels    = local.labels
  }
  spec {
    selector = { "app.kubernetes.io/name" = "keycloak" }
    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }
}

# 공개 주소 — 로그인에 필요한 경로만. /admin, master realm 은 인터넷에서 404/리다이렉트.
resource "kubectl_manifest" "route_public" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata   = { name = "keycloak-public", namespace = local.namespace, labels = local.labels }
    spec = {
      parentRefs = [{ name = var.gateway.name, namespace = var.gateway.namespace }]
      hostnames  = [var.public_hostname]
      rules = [
        {
          matches = concat(
            [for r in var.public_realms : { path = { type = "PathPrefix", value = "/realms/${r}" } }],
            [{ path = { type = "PathPrefix", value = "/resources" } }],
          )
          backendRefs = [{ name = kubernetes_service_v1.keycloak.metadata[0].name, port = 80 }]
        },
        {
          # 그 밖의 모든 경로(/admin, /realms/master ...) → 서비스 홈으로
          matches = [{ path = { type = "PathPrefix", value = "/" } }]
          filters = [{ type = "RequestRedirect", requestRedirect = { scheme = "https", hostname = "claudharmony.io", path = { type = "ReplaceFullPath", replaceFullPath = "/" }, statusCode = 302 } }]
        },
      ]
    }
  })
}

# 관리 주소 — 사무실 Mac 의 http://auth.localhost (인터넷 터널은 이 호스트를 받지 않는다)
resource "kubectl_manifest" "route_admin" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata   = { name = "keycloak-admin", namespace = local.namespace, labels = local.labels }
    spec = {
      parentRefs = [{ name = var.gateway.name, namespace = var.gateway.namespace }]
      hostnames  = [var.admin_hostname]
      rules      = [{ backendRefs = [{ name = kubernetes_service_v1.keycloak.metadata[0].name, port = 80 }] }]
    }
  })
}
