variable "cluster_name" {
  description = "kind 클러스터 이름"
  type        = string
  default     = "claudharmony"
}

variable "node_image" {
  description = "Kubernetes 노드 이미지 (kind v0.33.0 릴리스 노트의 digest 고정)"
  type        = string
  default     = "kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5"
}

variable "workers" {
  description = "worker 노드 수"
  type        = number
  default     = 1
}

variable "http_host_port" {
  description = "호스트(Mac)에 열 HTTP 포트 → Gateway NodePort 30080"
  type        = number
  default     = 80
}

variable "kubeconfig_path" {
  description = "이 클러스터 전용 kubeconfig (기본 ~/.kube/config 의 current-context 를 건드리지 않기 위해 분리)"
  type        = string
  default     = "~/.claudharmony/kubeconfig"
}
