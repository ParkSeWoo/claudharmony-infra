terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker" }
  }
}

locals {
  src_files = sort(setunion(
    fileset(var.source_dir, "Dockerfile"),
    fileset(var.source_dir, "*.gradle"),
    fileset(var.source_dir, "src/**"),
  ))

  # 소스가 바뀌면 이미지 태그가 바뀌고 → 컨테이너 재생성
  src_hash  = substr(sha1(join("", [for f in local.src_files : filesha1("${var.source_dir}/${f}")])), 0, 12)
  image_ref = "${var.image_repo}:${local.src_hash}"
}

# provider 의 내장 빌드(legacy builder)는 Docker Desktop(containerd store)에서 실패하므로
# docker CLI(BuildKit)로 빌드한다.
resource "terraform_data" "build" {
  triggers_replace = [local.image_ref]

  provisioner "local-exec" {
    command = "docker build -t ${local.image_ref} -t ${var.image_repo}:latest ${var.source_dir}"
  }
}

resource "docker_container" "this" {
  name        = var.name
  image       = local.image_ref
  restart     = "unless-stopped"
  memory      = var.memory_mb
  memory_swap = var.memory_mb * 2
  env         = [for k, v in var.env : "${k}=${v}"]

  # 외부 포트 노출 없음 — reverse-proxy 를 통해서만 접근
  networks_advanced {
    name    = var.network_name
    aliases = [var.name]
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
    for_each = merge(var.labels, { "claudharmony.service" = var.name })
    content {
      label = labels.key
      value = labels.value
    }
  }

  depends_on = [terraform_data.build]
}
