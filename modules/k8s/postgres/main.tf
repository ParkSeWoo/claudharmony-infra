terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    kubectl    = { source = "alekc/kubectl" }
    random     = { source = "hashicorp/random" }
  }
}

# 환경별 PostgreSQL (CloudNativePG Cluster)
#
#   원칙: 도메인 규칙은 애플리케이션에, DB 는 저장·조회만.
#         스키마는 앱 저장소의 마이그레이션(Flyway)이 관리 — 여기서는 DB/계정/확장만 만든다.
#
#   만들어지는 것 (Namespace = 환경)
#     Service  pg-rw (읽기·쓰기, primary) / pg-ro (읽기 전용 replica) / pg-r (아무 인스턴스)
#     Secret   pg-app      — 앱 계정 app (username, password, uri, jdbc-uri ...) : CNPG 가 생성
#     Secret   pg-readonly — 조회 전용 계정 readonly (콘솔·분석용)          : 여기서 생성

variable "namespace" {
  type = string
}

variable "name" {
  type    = string
  default = "pg"
}

variable "image" {
  description = "PostgreSQL 이미지 (PostGIS 포함)"
  type        = string
  default     = "ghcr.io/cloudnative-pg/postgis:18.6-3.6.4-standard-trixie"
}

variable "instances" {
  description = "인스턴스 수 (1 = 단일, 2 이상 = primary + replica, 자동 장애조치)"
  type        = number
  default     = 1
}

variable "storage_size" {
  type    = string
  default = "5Gi"
}

variable "memory_mb" {
  type    = number
  default = 512
}

variable "database" {
  type    = string
  default = "claudharmony"
}

variable "local_node_port" {
  description = "로컬 DB 툴 접속용 NodePort (kind Docker 네트워크 안에서만 닿음 — Mac 은 scripts/db.sh 의 프록시로). null 이면 없음"
  type        = number
  default     = null
}

variable "extensions" {
  description = "앱 DB 에 만들 확장"
  type        = list(string)
  default     = ["postgis"]
}

resource "random_password" "readonly" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "readonly" {
  metadata {
    name      = "${var.name}-readonly"
    namespace = var.namespace
    labels    = { "cnpg.io/reload" = "true" }
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "readonly"
    password = random_password.readonly.result
  }
}

resource "kubectl_manifest" "cluster" {
  yaml_body = yamlencode({
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = { "app.kubernetes.io/part-of" = "claudharmony", "app.kubernetes.io/managed-by" = "terraform" }
    }
    spec = {
      instances = var.instances
      imageName = var.image

      storage = { size = var.storage_size }

      resources = {
        requests = { cpu = "100m", memory = "${var.memory_mb}Mi" }
        limits   = { memory = "${var.memory_mb}Mi" }
      }

      # 작은 인스턴스용 튜닝 (메모리의 ~25% 를 shared_buffers)
      postgresql = {
        parameters = {
          shared_buffers             = "${floor(var.memory_mb / 4)}MB"
          max_connections            = "50"
          timezone                   = "Asia/Seoul"
          log_min_duration_statement = "500" # 0.5초 넘는 쿼리 로그
        }
      }

      bootstrap = {
        initdb = {
          database               = var.database
          owner                  = "app" # → Secret pg-app 자동 생성
          postInitApplicationSQL = [for e in var.extensions : "CREATE EXTENSION IF NOT EXISTS ${e};"]
        }
      }

      # 선언형 계정 관리 — Operator 가 계속 맞춰 준다
      managed = {
        roles = [{
          name            = "readonly"
          ensure          = "present"
          login           = true
          connectionLimit = 5
          comment         = "조회 전용 (어드민 콘솔·분석)"
          inRoles         = ["pg_read_all_data"]
          passwordSecret  = { name = kubernetes_secret_v1.readonly.metadata[0].name }
        }]
      }
    }
  })

  wait_for {
    field {
      key   = "status.phase"
      value = "Cluster in healthy state"
    }
  }

  timeouts {
    create = "10m"
  }
}

# 로컬 접속용 — kubectl port-forward 는 클라이언트가 끊을 때 DB 쪽 리셋으로 종료되는 한계가 있어
# NodePort(+ Mac 의 127.0.0.1 전용 socat 프록시 컨테이너)로 안정적으로 연결한다.
# 호스트 포트 매핑이 없으므로 인터넷/사무실 LAN 에서는 닿지 않는다.
resource "kubernetes_service_v1" "local" {
  count = var.local_node_port == null ? 0 : 1

  metadata {
    name      = "${var.name}-local"
    namespace = var.namespace
    labels    = { "app.kubernetes.io/part-of" = "claudharmony", "claudharmony.io/purpose" = "local-db-access" }
  }

  spec {
    type     = "NodePort"
    selector = { "cnpg.io/cluster" = var.name, "cnpg.io/instanceRole" = "primary" }

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
      node_port   = var.local_node_port
    }
  }

  depends_on = [kubectl_manifest.cluster]
}

output "host" {
  description = "앱이 접속할 주소 (읽기·쓰기)"
  value       = "${var.name}-rw.${var.namespace}.svc.cluster.local"
}

output "jdbc_url" {
  value = "jdbc:postgresql://${var.name}-rw.${var.namespace}.svc.cluster.local:5432/${var.database}"
}

output "app_secret" {
  value = "${var.name}-app"
}

output "readonly_secret" {
  value = kubernetes_secret_v1.readonly.metadata[0].name
}
