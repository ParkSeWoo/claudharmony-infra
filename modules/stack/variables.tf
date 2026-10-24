variable "environment" {
  description = "환경 이름 (dev / prd)"
  type        = string
}

variable "public_port" {
  description = "호스트에 바인딩할 nginx 포트"
  type        = number
}

variable "server_name" {
  description = "도메인 (구매 전이면 _)"
  type        = string
  default     = "_"
}

variable "enable_tunnel" {
  description = "Cloudflare Quick Tunnel 로 외부 공개 (이중 NAT 로 포트포워딩 불가)"
  type        = bool
  default     = true
}

variable "services" {
  description = "서비스 카탈로그 (services.auto.tfvars.json). key = 서비스 이름 = 내부 DNS 이름"
  type = map(object({
    port        = optional(number, 8080)
    route_path  = optional(string) # nginx location. null 이면 외부 비공개
    health_path = optional(string, "/actuator/health")
    memory_mb   = optional(number, 512)
    env         = optional(map(string), {})
  }))
}

variable "images" {
  description = "배포된 이미지 (images.auto.tfvars.json — 배포 워크플로가 갱신). key = 서비스 이름"
  type        = map(string)
}
