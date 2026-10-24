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
  services  = var.services
  images    = var.images
}

output "env" {
  value = module.env
}
