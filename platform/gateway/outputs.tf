output "gateway" {
  description = "HTTPRoute 의 parentRefs 에 쓸 값"
  value       = { name = "claudharmony", namespace = local.namespace }
}

output "gateway_service" {
  description = "클러스터 내부에서 Gateway 로 들어가는 주소 (터널이 사용)"
  value       = "claudharmony-gateway.${local.namespace}.svc.cluster.local:80"
}
