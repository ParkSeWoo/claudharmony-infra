terraform {
  required_version = ">= 1.6"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.10.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "local" {}
}

# scripts/infra.sh realms 가 port-forward 주소와 bootstrap client 비밀을 넣어 준다
provider "keycloak" {
  url           = var.keycloak_url
  realm         = "master"
  client_id     = "terraform-bootstrap"
  client_secret = var.keycloak_client_secret
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}
