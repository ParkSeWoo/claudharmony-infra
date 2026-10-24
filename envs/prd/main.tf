variable "services" {
  type = any
}

variable "images" {
  type = map(string)
}

module "env" {
  source = "../../modules/k8s/env"

  environment = "prd"
  # 빈 목록 = 모든 Host 를 받는 기본(catch-all) 라우트
  hostnames = []
  # 외부 공개는 platform/edge 의 고정 도메인 터널이 담당 → 임시(quick) 터널 끔
  enable_tunnel = false
  # PostgreSQL 18 + PostGIS (CloudNativePG) — 앱 계정 접속 정보는 database = true 인 서비스에 주입
  database = { instances = 1, storage_size = "5Gi", local_port = 32432, memory_mb = 512 }

  services = var.services
  images   = var.images
}

output "env" {
  value = module.env
}
