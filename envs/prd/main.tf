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
  services      = var.services
  images        = var.images
}

output "env" {
  value = module.env
}
