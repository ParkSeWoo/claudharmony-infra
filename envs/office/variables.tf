variable "environment" {
  description = "환경 이름"
  type        = string
  default     = "office"
}

variable "docker_host" {
  description = "Docker daemon 주소"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "public_port" {
  description = "외부에 노출할 nginx 포트"
  type        = number
  default     = 80
}

variable "server_name" {
  description = "도메인 (구매 전이면 _)"
  type        = string
  default     = "_"
}

variable "services" {
  description = <<-EOT
    서비스 카탈로그. 어드민 콘솔은 services.auto.tfvars.json 만 생성/수정한다.
    key = 서비스 이름(컨테이너/내부 DNS 이름)
  EOT
  type = map(object({
    source_dir  = string # infra 루트 기준 상대 경로 (예: apps/hello)
    port        = optional(number, 8080)
    route_path  = optional(string) # nginx location. null 이면 외부 비공개
    health_path = optional(string, "/actuator/health")
    memory_mb   = optional(number, 512)
    env         = optional(map(string), {})
  }))
}

variable "enable_tunnel" {
  description = "Cloudflare Quick Tunnel 로 외부 공개 (이중 NAT 로 포트포워딩 불가)"
  type        = bool
  default     = true
}
