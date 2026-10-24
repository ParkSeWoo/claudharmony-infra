terraform {
  required_version = ">= 1.6"

  # kind 클러스터는 kind CLI 로 만든다 (terraform_data + local-exec)
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  backend "local" {}
}
