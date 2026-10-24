locals {
  infra_root = abspath("${path.root}/../..")

  labels = {
    "claudharmony.managed-by"  = "terraform"
    "claudharmony.environment" = var.environment
  }

  # 긴 경로가 먼저 매칭되도록 정렬 (nginx prefix location 은 최장 일치지만 가독성 위해)
  routes = [
    for name, s in var.services : {
      path     = s.route_path
      upstream = module.service[name].upstream
    } if s.route_path != null
  ]
}

# VPC 역할
module "network" {
  source = "../../modules/network"
  name   = "claudharmony-${var.environment}"
  labels = local.labels
}

# Compute 역할 — 서비스 카탈로그(services.auto.tfvars.json)에서 생성
module "service" {
  source   = "../../modules/app-service"
  for_each = var.services

  name         = each.key
  source_dir   = "${local.infra_root}/${each.value.source_dir}"
  image_repo   = "claudharmony/${each.key}"
  port         = each.value.port
  health_path  = each.value.health_path
  memory_mb    = each.value.memory_mb
  env          = each.value.env
  network_name = module.network.name
  labels       = local.labels
}

# Load Balancer 역할
module "proxy" {
  source       = "../../modules/reverse-proxy"
  name         = "nginx"
  network_name = module.network.name
  listen_port  = var.public_port
  server_name  = var.server_name
  labels       = local.labels
  routes       = local.routes
}
