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

output "database" {
  value = var.database == null ? null : {
    host            = module.postgres[0].host
    jdbc_url        = module.postgres[0].jdbc_url
    app_secret      = module.postgres[0].app_secret
    readonly_secret = module.postgres[0].readonly_secret
  }
}
