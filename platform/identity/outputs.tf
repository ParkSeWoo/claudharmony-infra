output "issuer_base" {
  description = "토큰 issuer 앞부분 — 실제 issuer 는 <이 값>/realms/<realm>"
  value       = "https://${var.public_hostname}"
}

output "admin_console" {
  value = "http://${var.admin_hostname}/admin/"
}

output "internal_url" {
  description = "클러스터 안 앱이 JWKS·토큰 교환에 쓰는 주소"
  value       = "http://keycloak.${local.namespace}.svc.cluster.local"
}
