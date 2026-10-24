output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "urls" {
  value = [for h in var.hostnames : "https://${h}"]
}
