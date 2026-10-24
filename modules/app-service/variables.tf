variable "name" {
  description = "서비스 이름 (컨테이너 이름 = 내부 DNS 이름)"
  type        = string
}

variable "source_dir" {
  description = "Dockerfile 이 있는 앱 소스 디렉토리"
  type        = string
}

variable "image_repo" {
  description = "로컬 이미지 저장소 이름"
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
