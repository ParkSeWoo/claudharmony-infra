output "issuers" {
  value = { for k, v in var.realms : k => "${var.public_base}/realms/${v.realm}" }
}

output "broker_redirect_uris" {
  description = "소셜 로그인 서비스 콘솔에 등록할 redirect URI (<alias> = google | github | kakao)"
  value       = { for k, v in var.realms : k => "${var.public_base}/realms/${v.realm}/broker/<alias>/endpoint" }
}
