variable "name" {
  description = "컨테이너 이름 (환경 prefix 포함, 예: dev-hello-app)"
  type        = string
}

variable "alias" {
  description = "네트워크 내부 DNS 이름 (예: hello-app)"
  type        = string
}

variable "image" {
  description = "배포할 이미지 (예: claudharmony/hello-app:dev-1a2b3c4)"
  type        = string
}

variable "port" {
  description = "컨테이너 내부 포트"
  type        = number
  default     = 8080
}

variable "network_name" {
  description = "연결할 Docker 네트워크"
  type        = string
}

variable "env" {
  description = "환경 변수"
  type        = map(string)
  default     = {}
}

variable "health_path" {
  description = "헬스체크 경로 (빈 문자열이면 비활성)"
  type        = string
  default     = "/actuator/health"
}

variable "memory_mb" {
  description = "메모리 제한 (MB)"
  type        = number
  default     = 512
}

variable "labels" {
  description = "공통 라벨"
  type        = map(string)
  default     = {}
}
