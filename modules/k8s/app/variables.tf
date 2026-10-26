variable "name" {
  description = "서비스 이름 (Deployment / Service 이름)"
  type        = string
}

variable "namespace" {
  type = string
}

variable "image" {
  description = "배포할 이미지 (kind 노드에 미리 load 되어 있어야 함)"
  type        = string
}

variable "port" {
  type    = number
  default = 8080
}

variable "replicas" {
  type    = number
  default = 1
}

variable "env" {
  type    = map(string)
  default = {}
}

variable "secret_env" {
  description = "Secret 에서 읽는 환경 변수: 이름 → { secret, key, optional }. optional = true 면 키가 없어도 Pod 가 뜬다(변수만 빠짐)"
  type = map(object({
    secret   = string
    key      = string
    optional = optional(bool, false)
  }))
  default = {}
}

variable "cpu_request" {
  type    = string
  default = "100m"
}

variable "memory_mb" {
  description = "메모리 request = limit (MB)"
  type        = number
  default     = 512
}

variable "liveness_path" {
  type    = string
  default = "/actuator/health/liveness"
}

variable "readiness_path" {
  type    = string
  default = "/actuator/health/readiness"
}

variable "route" {
  description = "외부 노출 설정. null 이면 내부 전용 (HTTPRoute 미생성)"
  type = object({
    path      = string
    hostnames = optional(list(string), []) # 빈 목록 = 모든 Host (catch-all)
  })
  default = null
}

variable "gateway" {
  description = "HTTPRoute 가 붙을 Gateway"
  type = object({
    name      = string
    namespace = string
  })
}

variable "service_account" {
  description = "Pod 가 쓸 ServiceAccount (null = default). K8s API 를 호출하는 서비스(console)용"
  type        = string
  default     = null
}

variable "pod_annotations" {
  description = "Pod 템플릿 annotation — 값이 바뀌면 Pod 가 다시 뜬다 (예: 읽는 Secret 의 해시)"
  type        = map(string)
  default     = {}
}
