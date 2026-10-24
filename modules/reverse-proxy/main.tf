terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker" }
  }
}

locals {
  config = templatefile("${path.module}/templates/default.conf.tftpl", {
    routes      = var.routes
    server_name = var.server_name
  })
}

resource "docker_image" "this" {
  name         = var.image
  keep_locally = true
}

resource "docker_container" "this" {
  name    = var.name
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  ports {
    internal = 80
    external = var.listen_port
    ip       = "0.0.0.0"
  }

  # 설정이 바뀌면 컨테이너 재생성
  upload {
    file    = "/etc/nginx/conf.d/default.conf"
    content = local.config
  }

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

output "rendered_config" {
  value = local.config
}
