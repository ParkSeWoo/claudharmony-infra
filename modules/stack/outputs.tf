output "local_url" {
  value = "http://localhost:${var.public_port}"
}

output "tunnel_container" {
  value = var.enable_tunnel ? module.tunnel["tunnel"].name : null
}

output "services" {
  description = "어드민 콘솔이 읽어갈 서비스 상태 (terraform output -json)"
  value = {
    for name, m in module.service : name => {
      container = m.name
      image     = m.image
      upstream  = m.upstream
      route     = var.services[name].route_path
    }
  }
}
