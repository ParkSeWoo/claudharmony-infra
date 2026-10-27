variable "kubeconfig_path" {
  type    = string
  default = "~/.claudharmony/kubeconfig"
}

variable "kube_context" {
  type    = string
  default = "kind-claudharmony"
}

variable "keycloak_image" {
  description = "기본 이미지 (공식). images.auto.tfvars.json 에 keycloak 이 있으면 그쪽이 우선"
  type        = string
  default     = "quay.io/keycloak/keycloak:26.7.5"
}

variable "images" {
  description = "배포 기록 — scripts/deploy.sh identity keycloak <image> 가 갱신 (claudharmony-keycloak 저장소: 공식 이미지 + 로그인 테마)"
  type        = map(string)
  default     = {}
}

variable "public_hostname" {
  description = "로그인 화면·토큰 발급 주소 (인터넷 공개, Cloudflare 터널 경유)"
  type        = string
  default     = "auth.claudharmony.io"
}

variable "public_aliases" {
  description = "공개 주소와 같은 로그인 경로를 받는 다른 호스트 (도메인 이전 병행 기간). 토큰 발급자(iss)는 public_hostname 하나로 고정"
  type        = list(string)
  default     = ["auth.cloudharmony.io"]
}

variable "home_hostname" {
  description = "공개 주소에서 로그인 외 경로(/admin 등)를 돌려보낼 서비스 홈"
  type        = string
  default     = "claudharmony.io"
}

variable "admin_hostname" {
  description = "관리 콘솔 주소 (사무실 Mac 에서만 — 인터넷에는 /admin 을 열지 않는다)"
  type        = string
  default     = "auth.localhost"
}

variable "public_realms" {
  description = "인터넷에 여는 realm (master 는 관리용이라 제외)"
  type        = list(string)
  default     = ["claudharmony", "claudharmony-dev"]
}

variable "memory_mb" {
  type    = number
  default = 1024
}

variable "gateway" {
  type = object({
    name      = string
    namespace = string
  })
  default = { name = "claudharmony", namespace = "envoy-gateway-system" }
}
