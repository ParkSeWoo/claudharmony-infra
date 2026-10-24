terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker" }
  }
}

# 이미지는 앱 저장소의 배포 워크플로가 같은 호스트에서 미리 빌드해 둔다.
resource "docker_container" "this" {
  name        = var.name
  image       = var.image
  restart     = "unless-stopped"
  memory      = var.memory_mb
  memory_swap = var.memory_mb * 2
  env         = [for k, v in var.env : "${k}=${v}"]

  # 외부 포트 노출 없음 — reverse-proxy 를 통해서만 접근
  networks_advanced {
    name    = var.network_name
    aliases = [var.alias]
  }

  dynamic "healthcheck" {
    for_each = var.health_path == "" ? [] : [1]
    content {
      test         = ["CMD-SHELL", "bash -c 'exec 3<>/dev/tcp/127.0.0.1/${var.port} && printf \"GET ${var.health_path} HTTP/1.0\\r\\n\\r\\n\" >&3 && grep -q UP <&3'"]
      interval     = "10s"
      timeout      = "3s"
      retries      = 5
      start_period = "30s"
    }
  }

  dynamic "labels" {
    for_each = merge(var.labels, { "claudharmony.service" = var.alias })
    content {
      label = labels.key
      value = labels.value
    }
  }
}
