variable "services" {
  type = any
}

variable "images" {
  type = map(string)
}

variable "app_secrets" {
  type      = map(string)
  default   = {}
  sensitive = true
}

module "env" {
  source = "../../modules/k8s/env"

  environment = "dev"
  # 빈 목록 = 모든 Host 를 받는 기본(catch-all) 라우트
  hostnames = ["dev.localhost", "dev.claudharmony.io"]
  # 외부 공개는 platform/edge 의 고정 도메인 터널이 담당 → 임시(quick) 터널 끔
  enable_tunnel = false
  # PostgreSQL 18 + PostGIS (CloudNativePG) — 앱 계정 접속 정보는 database = true 인 서비스에 주입
  database = { instances = 1, storage_size = "5Gi", local_port = 31432, memory_mb = 384 }

  services    = var.services
  images      = var.images
  app_secrets = var.app_secrets
}

output "env" {
  value = module.env
}
