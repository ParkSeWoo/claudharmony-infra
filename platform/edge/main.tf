# 2.5단계 — Edge: 고정 도메인(cloudharmony.io · 옛 claudharmony.io) → Cloudflare Tunnel → 클러스터 Gateway
#
#   사용자 ─HTTPS→ Cloudflare(인증서·DNS) ═터널(아웃바운드)═ cloudflared Pod(ns edge) ─HTTP→ Gateway → HTTPRoute
#
# Quick tunnel(랜덤 주소)과 달리 named tunnel 은 주소가 고정되고, 커넥터를 여러 개 띄워 이중화할 수 있다.

data "cloudflare_zone" "this" {
  for_each = var.zones
  filter   = { name = each.key }
}

locals {
  # 호스트 → zone (DNS 레코드 key 는 호스트 이름 그대로 — 옛 state 주소 유지)
  host_zone = merge([for z, hosts in var.zones : { for h in hosts : h => z }]...)
  hostnames = sort(keys(local.host_zone))
}

# ① 터널 (Cloudflare 쪽 객체) — 설정은 Cloudflare 가 보관(config_src = cloudflare)
resource "random_bytes" "tunnel_secret" {
  length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id    = var.cloudflare_account_id
  name          = "claudharmony-office"
  config_src    = "cloudflare"
  tunnel_secret = random_bytes.tunnel_secret.base64
}

# ② 터널 라우팅 — 모든 호스트를 Gateway 로. Host 헤더는 원래 값 그대로 → HTTPRoute 가 dev/prd 를 나눈다
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = concat(
      [for h in local.hostnames : { hostname = h, service = var.gateway_service }],
      [{ service = "http_status:404" }] # 마지막 규칙은 반드시 catch-all
    )
  }
}

# ③ DNS — 각 호스트를 터널로 (proxied = Cloudflare 가 HTTPS 종단)
resource "cloudflare_dns_record" "this" {
  for_each = local.host_zone

  zone_id = data.cloudflare_zone.this[each.value].zone_id
  name    = each.key
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # proxied 레코드는 1 = automatic
  comment = "managed by terraform (claudharmony-infra/platform/edge)"
}

# ④ 커넥터 — 클러스터 안 cloudflared 가 토큰으로 터널에 붙는다
data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

resource "kubernetes_namespace_v1" "edge" {
  metadata {
    name   = "edge"
    labels = { "app.kubernetes.io/part-of" = "claudharmony" }
  }
}

resource "kubernetes_secret_v1" "tunnel_token" {
  metadata {
    name      = "cloudflared-token"
    namespace = kubernetes_namespace_v1.edge.metadata[0].name
  }
  data = { token = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token }
}

resource "kubernetes_deployment_v1" "cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = kubernetes_namespace_v1.edge.metadata[0].name
    labels    = { "app.kubernetes.io/name" = "cloudflared", "app.kubernetes.io/managed-by" = "terraform" }
  }

  spec {
    replicas = var.connector_replicas

    selector {
      match_labels = { "app.kubernetes.io/name" = "cloudflared" }
    }

    template {
      metadata {
        labels = { "app.kubernetes.io/name" = "cloudflared" }
        # 토큰이 바뀌면 Pod 재시작
        annotations = { "claudharmony.io/token-sha" = sha1(data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token) }
      }

      spec {
        container {
          name  = "cloudflared"
          image = var.cloudflared_image
          args  = ["tunnel", "--no-autoupdate", "--metrics", "0.0.0.0:2000", "run"]

          env {
            name = "TUNNEL_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.tunnel_token.metadata[0].name
                key  = "token"
              }
            }
          }

          port {
            name           = "metrics"
            container_port = 2000
          }

          # /ready: Cloudflare 엣지와 연결이 하나 이상 살아 있을 때 200
          readiness_probe {
            http_get {
              path = "/ready"
              port = "metrics"
            }
            period_seconds = 10
          }

          liveness_probe {
            http_get {
              path = "/ready"
              port = "metrics"
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            failure_threshold     = 4
          }

          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { memory = "128Mi" }
          }
        }
      }
    }
  }
}

# ⑤ 옛 도메인 301 — Cloudflare 엣지에서 바로 돌려보낸다 (터널·클러스터까지 오지 않음)
#   https://dev.claudharmony.io/a?b=1 → https://dev.cloudharmony.io/a?b=1
#   DNS 레코드는 남겨 둔다 (proxied 레코드가 있어야 Cloudflare 가 요청을 받아 규칙을 적용)
resource "cloudflare_ruleset" "redirect" {
  for_each = var.redirect_zones

  zone_id     = data.cloudflare_zone.this[each.key].zone_id
  name        = "redirect ${each.key} → ${each.value}"
  description = "managed by terraform (claudharmony-infra/platform/edge)"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [{
    ref         = "old_domain_301"
    description = "${each.key} → ${each.value} (같은 호스트 앞부분·경로·쿼리)"
    expression  = "true"
    action      = "redirect"
    action_parameters = {
      from_value = {
        status_code = 301
        target_url = {
          # full_uri 에 쿼리까지 들어 있으므로 preserve_query_string 은 끈다 (켜면 쿼리가 두 번 붙음)
          expression = "wildcard_replace(http.request.full_uri, r\"https://*${each.key}/*\", r\"https://$${1}${each.value}/$${2}\")"
        }
        preserve_query_string = false
      }
    }
  }]
}
