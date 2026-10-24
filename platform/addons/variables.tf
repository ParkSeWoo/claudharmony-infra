variable "kubeconfig_path" {
  type    = string
  default = "~/.claudharmony/kubeconfig"
}

variable "kube_context" {
  type    = string
  default = "kind-claudharmony"
}

variable "metrics_server_version" {
  description = "metrics-server Helm chart 버전"
  type        = string
  default     = "3.14.0"
}
