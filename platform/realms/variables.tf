variable "kubeconfig_path" {
  type    = string
  default = "~/.claudharmony/kubeconfig"
}

variable "kube_context" {
  type    = string
  default = "kind-claudharmony"
}

variable "keycloak_url" {
  type = string
}

variable "keycloak_client_secret" {
  type      = string
  sensitive = true
}

variable "public_base" {
  description = "토큰 issuer 앞부분 (platform/identity 의 공개 주소)"
  type        = string
  default     = "https://auth.claudharmony.io"
}

variable "internal_base" {
  description = "클러스터 안에서 Keycloak 에 닿는 주소 (JWKS·토큰 교환)"
  type        = string
  default     = "http://keycloak.identity.svc.cluster.local"
}

# 환경 = realm 하나. 사용자·세션·client 가 환경끼리 섞이지 않는다.
variable "realms" {
  type = map(object({
    realm        = string
    display_name = string
    web_urls     = list(string)     # 로그인 후 돌아올 web 주소 (redirect URI / CORS origin)
    console_urls = list(string)     # 비어 있으면 console client 를 만들지 않음
    test_user    = bool             # 로그인 확인용 사용자 (dev 만)
    login_theme  = optional(string) # null = Keycloak 기본. "claudharmony" 는 커스텀 이미지 배포 후에만 (없는 테마를 지정하면 로그인 화면 오류)
  }))
  default = {
    prd = {
      realm        = "claudharmony"
      display_name = "클라우드 하모니"
      web_urls     = ["https://claudharmony.io", "https://www.claudharmony.io", "http://localhost"]
      console_urls = ["https://console.claudharmony.io", "http://console.localhost"]
      test_user    = false
    }
    dev = {
      realm        = "claudharmony-dev"
      display_name = "클라우드 하모니 (dev)"
      web_urls     = ["https://dev.claudharmony.io", "http://dev.localhost", "http://localhost:5173"]
      console_urls = []
      test_user    = true
      login_theme  = "claudharmony" # claudharmony-keycloak 이미지 (dev 먼저 확인)
    }
  }
}

# 소셜 로그인 — 각 서비스 개발자 콘솔에서 발급한 값. 비어 있으면 만들지 않는다.
# 값은 저장소 밖 ~/.claudharmony/identity.env 에 두고 scripts/infra.sh 가 읽는다. (docs/12-identity.md)
variable "social" {
  type = map(object({
    client_id     = string
    client_secret = string
  }))
  default   = {}
  sensitive = true
}

variable "master_frontend_url" {
  description = "master realm(관리자 로그인) 주소 — 사무실 Mac 전용"
  type        = string
  default     = "http://auth.localhost"
}
