terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    kubectl    = { source = "alekc/kubectl" }
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

module "service" {
  source   = "../app"
  for_each = local.deployed

  name      = each.key
  namespace = kubernetes_namespace_v1.this.metadata[0].name
  image     = var.images[each.key]
  port      = each.value.port
  replicas  = each.value.replicas
  memory_mb = each.value.memory_mb
  env       = merge({ APP_ENV = var.environment }, each.value.env)
  gateway   = var.gateway
  route     = each.value.route_path == null ? null : { path = each.value.route_path, hostnames = var.hostnames }
}

module "tunnel" {
  source   = "../tunnel"
  for_each = var.enable_tunnel ? { tunnel = true } : {}

  namespace   = kubernetes_namespace_v1.this.metadata[0].name
  target_url  = "http://${var.gateway_service}"
  host_header = length(var.hostnames) > 0 ? var.hostnames[0] : null
}
