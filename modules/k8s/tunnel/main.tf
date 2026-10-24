terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
  }
}

variable "namespace" {
  type = string
}

variable "target_url" {
  description = "터널이 전달할 주소 (Gateway Service)"
  type        = string
}

variable "host_header" {
  description = "Gateway 로 보낼 Host 헤더 (HTTPRoute hostnames 매칭용). null 이면 원래 Host 유지"
  type        = string
  default     = null
}

variable "image" {
  type    = string
  default = "cloudflare/cloudflared:2025.10.0"
}

# Cloudflare Quick Tunnel — 클러스터 안에서 바깥으로 연결해 https://*.trycloudflare.com 발급
# Pod 가 재시작되면 URL 이 바뀐다 (도메인 구매 후 named tunnel 로 전환)
resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = "tunnel"
    namespace = var.namespace
    labels    = { "app.kubernetes.io/name" = "tunnel", "app.kubernetes.io/managed-by" = "terraform" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { "app.kubernetes.io/name" = "tunnel" }
    }

    template {
      metadata {
        labels = { "app.kubernetes.io/name" = "tunnel" }
      }

      spec {
        container {
          name  = "cloudflared"
          image = var.image
          args = concat(
            ["tunnel", "--no-autoupdate", "--url", var.target_url],
            var.host_header == null ? [] : ["--http-host-header", var.host_header]
          )

          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { memory = "128Mi" }
          }
        }
      }
    }
  }
}

output "name" {
  value = kubernetes_deployment_v1.this.metadata[0].name
}
