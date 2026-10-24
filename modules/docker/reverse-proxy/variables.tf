variable "name" {
  description = "프록시 컨테이너 이름"
  type        = string
  default     = "nginx"
}

variable "image" {
  description = "nginx 이미지"
  type        = string
  default     = "nginx:1.27-alpine"
}

variable "network_name" {
  description = "연결할 Docker 네트워크"
  type        = string
}

variable "listen_port" {
  description = "호스트에 바인딩할 외부 포트"
  type        = number
  default     = 80
}

variable "routes" {
  description = "경로 → upstream 라우팅 테이블 (클라우드의 Load Balancer 리스너 규칙 역할)"
  type = list(object({
    path     = string
    upstream = string
  }))
}

variable "server_name" {
  description = "도메인 (구매 전이면 _ 로 모든 요청 수신)"
  type        = string
  default     = "_"
}

variable "labels" {
  description = "공통 라벨"
  type        = map(string)
  default     = {}
}
