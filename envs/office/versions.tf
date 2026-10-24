terraform {
  required_version = ">= 1.6"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6"
    }
  }

  # TODO: 어드민 콘솔 단계에서 원격 state 로 전환 (S3/MinIO + lock 또는 Terraform HTTP backend)
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "docker" {
  host = var.docker_host
}
