# 관리자 콘솔 (claudharmony-console) — 환경이 아니라 "도구"라서 하나만 둔다
#   https://console.claudharmony.io  (Cloudflare Access 로 보호 — platform/edge)
#   http://console.localhost          (사무실 Mac)
#
# 1단계: 조회 전용. ServiceAccount 는 클러스터 전체 읽기만 가능 (Secret 제외)

variable "services" {
  type = any
}

variable "images" {
  type = map(string)
}

module "env" {
  source = "../../modules/k8s/env"

  environment   = "console"
  hostnames     = ["console.localhost", "console.cloudharmony.io", "console.claudharmony.io"]
  enable_tunnel = false
  services      = var.services
  images        = var.images
}

resource "kubernetes_service_account_v1" "console" {
  metadata {
    name      = "console"
    namespace = module.env.namespace
  }
}

# 읽기 전용 권한 — Secret 은 의도적으로 제외 (DB 비밀번호 등 노출 방지)
resource "kubernetes_cluster_role_v1" "console_read" {
  metadata {
    name = "claudharmony-console-read"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "nodes", "pods", "pods/log", "services", "events", "persistentvolumeclaims", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["gateway.networking.k8s.io"]
    resources  = ["gateways", "httproutes", "gatewayclasses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["postgresql.cnpg.io"]
    resources  = ["clusters", "backups", "scheduledbackups"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["pods", "nodes"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "console_read" {
  metadata {
    name = "claudharmony-console-read"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.console_read.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.console.metadata[0].name
    namespace = module.env.namespace
  }
}

output "env" {
  value = module.env
}
