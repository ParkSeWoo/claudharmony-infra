terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    kubectl    = { source = "alekc/kubectl" }
    random     = { source = "hashicorp/random" }
  }
}

locals {
  # 이미지가 아직 배포되지 않은 서비스는 건너뛴다
  deployed = { for k, v in var.services : k => v if contains(keys(var.images), k) }
}

# Namespace = 환경 경계 (AWS 의 계정/VPC, GCP 의 프로젝트에 해당)
resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.environment
    labels = {
      "claudharmony.io/environment"    = var.environment
      "claudharmony.io/gateway-access" = "true" # Gateway 에 HTTPRoute 를 붙일 수 있는 권한
    }
  }
}

# 앱 비밀값 (외부 API 키 등) — 서비스는 카탈로그 secret_env 에서 { secret = "app-secrets", key = ..., optional = true } 로 읽는다.
# 키가 아직 없으면 빈 Secret 이라 optional 참조는 변수 없이 뜬다. 값은 tfstate(저장소 밖)에만 남는다.
resource "kubernetes_secret_v1" "app" {
  metadata {
    name      = "app-secrets"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = { "app.kubernetes.io/managed-by" = "terraform" }
  }
  data = var.app_secrets
}

# 데이터베이스 (환경별 1개)
module "postgres" {
  source = "../postgres"
  count  = var.database == null ? 0 : 1

  namespace    = kubernetes_namespace_v1.this.metadata[0].name
  instances    = var.database.instances
  storage_size = var.database.storage_size
  memory_mb    = var.database.memory_mb

  local_node_port = var.database.local_port
}

locals {
  # database = true 인 서비스에 주입할 접속 정보 (비밀번호는 Secret 참조)
  db_env = var.database == null ? {} : { SPRING_DATASOURCE_URL = module.postgres[0].jdbc_url }
  db_secret_env = var.database == null ? {} : {
    SPRING_DATASOURCE_USERNAME = { secret = module.postgres[0].app_secret, key = "username", optional = false }
    SPRING_DATASOURCE_PASSWORD = { secret = module.postgres[0].app_secret, key = "password", optional = false }
  }
}

module "service" {
  source   = "../app"
  for_each = local.deployed

  name            = each.key
  namespace       = kubernetes_namespace_v1.this.metadata[0].name
  image           = var.images[each.key]
  port            = each.value.port
  replicas        = each.value.replicas
  memory_mb       = each.value.memory_mb
  env             = merge({ APP_ENV = var.environment }, each.value.database ? local.db_env : {}, each.value.env)
  secret_env      = merge(each.value.database ? local.db_secret_env : {}, each.value.secret_env)
  service_account = each.value.service_account
  gateway         = var.gateway
  route           = each.value.route_path == null ? null : { path = each.value.route_path, hostnames = var.hostnames }
}

module "tunnel" {
  source   = "../tunnel"
  for_each = var.enable_tunnel ? { tunnel = true } : {}

  namespace   = kubernetes_namespace_v1.this.metadata[0].name
  target_url  = "http://${var.gateway_service}"
  host_header = length(var.hostnames) > 0 ? var.hostnames[0] : null
}
