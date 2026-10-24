terraform {
  required_version = ">= 1.6"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    # CRD 기반 리소스(GatewayClass/Gateway/EnvoyProxy)는 plan 시점에 CRD 가 없어도 되는 kubectl provider 로 관리
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }

  backend "local" {}
}

provider "helm" {
  kubernetes = {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context
  }
}

provider "kubectl" {
  config_path      = pathexpand(var.kubeconfig_path)
  config_context   = var.kube_context
  load_config_file = true
}
