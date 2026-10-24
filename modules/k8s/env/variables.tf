variable "environment" {
  description = "환경 이름 = Namespace (dev / prd)"
  type        = string
}

variable "hostnames" {
  description = "이 환경 HTTPRoute 의 hostnames. 빈 목록이면 catch-all (prd)"
  type        = list(string)
  default     = []
}

variable "enable_tunnel" {
  type    = bool
  default = true
}

variable "gateway" {
  type = object({
    name      = string
    namespace = string
  })
  default = { name = "claudharmony", namespace = "envoy-gateway-system" }
}

variable "gateway_service" {
  type    = string
  default = "claudharmony-gateway.envoy-gateway-system.svc.cluster.local:80"
}

variable "services" {
  description = "서비스 카탈로그 (services.auto.tfvars.json). key = 서비스 이름"
  type = map(object({
    port            = optional(number, 8080)
    route_path      = optional(string) # null 이면 외부 비공개
    replicas        = optional(number, 1)
    memory_mb       = optional(number, 512)
    env             = optional(map(string), {})
    database        = optional(bool, false) # true 면 PostgreSQL 접속 정보(SPRING_DATASOURCE_*) 주입
    service_account = optional(string)      # K8s API 를 쓰는 서비스용
  }))
}

variable "database" {
  description = "환경 PostgreSQL (CloudNativePG). null 이면 만들지 않음"
  type = object({
    instances    = optional(number, 1)
    storage_size = optional(string, "5Gi")
    memory_mb    = optional(number, 512)
  })
  default = null
}

variable "images" {
  description = "배포된 이미지 (images.auto.tfvars.json — 배포 워크플로가 갱신). key = 서비스 이름"
  type        = map(string)
}
