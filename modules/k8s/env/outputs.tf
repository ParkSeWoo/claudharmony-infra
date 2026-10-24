output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "services" {
  description = "어드민 콘솔이 읽어갈 서비스 상태 (terraform output -json)"
  value = {
    for name, m in module.service : name => {
      deployment = m.name
      image      = m.image
      service    = m.service
      route      = var.services[name].route_path
    }
  }
}
