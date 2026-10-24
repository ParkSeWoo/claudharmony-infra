terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker" }
  }
}

variable "name" {
  description = "Docker 네트워크 이름 (클라우드의 VPC 역할)"
  type        = string
}

variable "labels" {
  description = "공통 라벨"
  type        = map(string)
  default     = {}
}

resource "docker_network" "this" {
  name   = var.name
  driver = "bridge"

  dynamic "labels" {
    for_each = var.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}

output "id" {
  value = docker_network.this.id
}

output "name" {
  value = docker_network.this.name
}
