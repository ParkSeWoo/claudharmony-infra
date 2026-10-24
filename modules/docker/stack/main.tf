terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker" }
  }
}

locals {
  prefix = var.environment

  labels = {
    "claudharmony.managed-by"  = "terraform"
    "claudharmony.environment" = var.environment
  }

  # 이미지가 아직 배포되지 않은 서비스는 건너뛴다
  deployed = { for k, v in var.services : k => v if contains(keys(var.images), k) }

  routes = [
    for name, s in local.deployed : {
      path     = s.route_path
      upstream = module.service[name].upstream
    } if s.route_path != null
  ]
}

# VPC 역할
module "network" {
  source = "../network"
  name   = "claudharmony-${local.prefix}"
  labels = local.labels
}

# Compute 역할
module "service" {
  source   = "../app-service"
  for_each = local.deployed

  name         = "${local.prefix}-${each.key}"
  alias        = each.key
  image        = var.images[each.key]
  port         = each.value.port
  health_path  = each.value.health_path
  memory_mb    = each.value.memory_mb
  env          = merge({ APP_ENV = var.environment }, each.value.env)
  network_name = module.network.name
  labels       = local.labels
}

# Load Balancer 역할
module "proxy" {
  source       = "../reverse-proxy"
  name         = "${local.prefix}-nginx"
  network_name = module.network.name
  listen_port  = var.public_port
  server_name  = var.server_name
  labels       = local.labels
  routes       = local.routes
}

# Internet Gateway 대용 — 이중 NAT 라 포트포워딩 불가, 터널로 외부 공개
module "tunnel" {
  source   = "../tunnel"
  for_each = var.enable_tunnel ? { tunnel = true } : {}

  name         = "${local.prefix}-tunnel"
  network_name = module.network.name
  target_url   = "http://${local.prefix}-nginx:80"
  labels       = local.labels
}
