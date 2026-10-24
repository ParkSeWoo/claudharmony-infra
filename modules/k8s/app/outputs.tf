output "name" {
  value = kubernetes_deployment_v1.this.metadata[0].name
}

output "image" {
  value = var.image
}

output "service" {
  value = "${kubernetes_service_v1.this.metadata[0].name}.${var.namespace}.svc.cluster.local"
}
