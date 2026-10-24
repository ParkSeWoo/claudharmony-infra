variable "kubeconfig_path" {
  type    = string
  default = "~/.claudharmony/kubeconfig"
}

variable "kube_context" {
  type    = string
  default = "kind-claudharmony"
}

variable "keycloak_image" {
  type    = string
  default = "quay.io/keycloak/keycloak:26.7.5"
}

variable "public_hostname" {
  description = "로그인 화면·토큰 발급 주소 (인터넷 공개, Cloudflare 터널 경유)"
  type        = string
  default     = "auth.claudharmony.io"
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
