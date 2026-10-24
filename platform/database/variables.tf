variable "kubeconfig_path" {
  type    = string
  default = "~/.claudharmony/kubeconfig"
}

variable "kube_context" {
  type    = string
  default = "kind-claudharmony"
}

variable "cnpg_chart_version" {
  description = "CloudNativePG Helm chart 버전 (0.29.1 = operator 1.30.1)"
  type        = string
  default     = "0.29.1"
}
