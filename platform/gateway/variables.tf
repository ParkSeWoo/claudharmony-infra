variable "kubeconfig_path" {
  type    = string
  default = "~/.claudharmony/kubeconfig"
}

variable "kube_context" {
  type    = string
  default = "kind-claudharmony"
}

variable "envoy_gateway_version" {
  description = "Envoy Gateway Helm chart 버전 (Gateway API CRD 포함)"
  type        = string
  default     = "v1.9.2"
}

variable "node_port" {
  description = "Gateway(Envoy) Service 의 NodePort — kind extraPortMappings(호스트 80)와 맞춰야 함"
  type        = number
  default     = 30080
}
