output "cluster_name" {
  value = var.cluster_name
}

output "kubeconfig" {
  value = local.kubeconfig
}

output "kube_context" {
  value = "kind-${var.cluster_name}"
}
