terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker" }
  }
}

variable "name" {
  description = "터널 컨테이너 이름"
  type        = string
  default     = "tunnel"
}

variable "image" {
  description = "cloudflared 이미지"
  type        = string
  default     = "cloudflare/cloudflared:2025.10.0"
}

variable "target_url" {
  description = "터널이 전달할 내부 주소 (reverse-proxy)"
  type        = string
}

variable "network_name" {
  description = "연결할 Docker 네트워크"
  type        = string
}

variable "labels" {
  description = "공통 라벨"
  type        = map(string)
  default     = {}
}

resource "docker_image" "this" {
  name         = var.image
  keep_locally = true
}

# Cloudflare Quick Tunnel — 계정/도메인/포트포워딩 없이 https://*.trycloudflare.com 발급.
# 이중 NAT 사무실에서 외부 공개용. 컨테이너가 재시작되면 URL 이 바뀐다.
# 도메인 구매 후에는 named tunnel(TUNNEL_TOKEN)로 전환.
resource "docker_container" "this" {
  name    = var.name
  image   = docker_image.this.image_id
  restart = "unless-stopped"
  command = ["tunnel", "--no-autoupdate", "--url", var.target_url]

  networks_advanced {
    name = var.network_name
  }

  dynamic "labels" {
    for_each = merge(var.labels, { "claudharmony.service" = var.name })
    content {
      label = labels.key
      value = labels.value
    }
  }
}

output "name" {
  value = docker_container.this.name
}
