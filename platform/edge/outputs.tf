output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "urls" {
  value = [for h in local.hostnames : "https://${h}"]
}
