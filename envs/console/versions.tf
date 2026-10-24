terraform {
  required_version = ">= 1.6"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # state 는 저장소 밖(~/.claudharmony/state/<env>.tfstate) — scripts/infra.sh 가 init 시 지정
  backend "local" {}
}

provider "kubernetes" {
  config_path    = pathexpand("~/.claudharmony/kubeconfig")
  config_context = "kind-claudharmony"
}

provider "kubectl" {
  config_path      = pathexpand("~/.claudharmony/kubeconfig")
  config_context   = "kind-claudharmony"
  load_config_file = true
}
