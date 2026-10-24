variable "cloudflare_account_id" {
  description = "Cloudflare Account ID (TF_VAR_cloudflare_account_id — infra.sh 가 주입)"
  type        = string
}

variable "domain" {
  description = "Cloudflare 에 등록된 도메인 (zone)"
  type        = string
  default     = "claudharmony.io"
}

variable "hostnames" {
  description = "터널로 받을 호스트 이름 → 모두 Gateway 로 보낸다. 환경 구분은 HTTPRoute hostnames 가 한다"
  type        = list(string)
  default     = ["claudharmony.io", "www.claudharmony.io", "dev.claudharmony.io", "auth.claudharmony.io", "console.claudharmony.io"]
}

variable "gateway_service" {
  description = "클러스터 안 Gateway 주소"
  type        = string
  default     = "http://claudharmony-gateway.envoy-gateway-system.svc.cluster.local:80"
}

variable "connector_replicas" {
  description = "cloudflared 커넥터 수 (named tunnel 은 여러 개를 띄워 이중화 가능)"
  type        = number
  default     = 2
}

variable "cloudflared_image" {
  type    = string
  default = "cloudflare/cloudflared:2025.10.0"
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.claudharmony/kubeconfig"
}

variable "kube_context" {
  type    = string
  default = "kind-claudharmony"
}

variable "console_allowed_emails" {
  description = "console 에 로그인 허용할 이메일 (infra.sh 가 ~/.claudharmony/cloudflare.env 의 CONSOLE_ALLOWED_EMAILS 로 주입)"
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.console_allowed_emails) > 0
    error_message = "CONSOLE_ALLOWED_EMAILS 가 비어 있으면 콘솔이 아무 보호 없이 열릴 수 있어 막는다."
  }
}
