output "name" {
  value = docker_container.this.name
}

output "upstream" {
  description = "reverse-proxy 에서 사용할 upstream 주소"
  value       = "${var.alias}:${var.port}"
}

output "image" {
  value = var.image
}
