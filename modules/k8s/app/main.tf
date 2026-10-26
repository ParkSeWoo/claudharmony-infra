terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    kubectl    = { source = "alekc/kubectl" }
  }
}

locals {
  labels = {
    "app.kubernetes.io/name"       = var.name
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "claudharmony"
  }
}

# Deployment: 원하는 상태(이미지, 복제 수)를 선언 → ReplicaSet → Pod
resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = { "app.kubernetes.io/name" = var.name }
    }

    # 무중단 배포: 새 Pod 가 Ready 된 뒤 옛 Pod 제거
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "1"
        max_unavailable = "0"
      }
    }

    template {
      metadata {
        labels      = local.labels
        annotations = var.pod_annotations
      }

      spec {
        service_account_name = var.service_account

        container {
          name              = var.name
          image             = var.image
          image_pull_policy = "IfNotPresent" # kind load 한 로컬 이미지 사용

          port {
            name           = "http"
            container_port = var.port
          }

          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "env" {
            for_each = var.secret_env
            content {
              name = env.key
              value_from {
                secret_key_ref {
                  name     = env.value.secret
                  key      = env.value.key
                  optional = env.value.optional
                }
              }
            }
          }

          resources {
            requests = { cpu = var.cpu_request, memory = "${var.memory_mb}Mi" }
            limits   = { memory = "${var.memory_mb}Mi" }
          }

          # 살아있나? 실패하면 컨테이너 재시작
          liveness_probe {
            http_get {
              path = var.liveness_path
              port = "http"
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          # 트래픽 받을 준비 됐나? 실패하면 Service 엔드포인트에서 제외
          readiness_probe {
            http_get {
              path = var.readiness_path
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }
      }
    }
  }

  wait_for_rollout = true

  timeouts {
    create = "5m"
    update = "5m"
  }
}

# Service: Pod 들 앞의 고정 내부 주소 (<name>.<namespace>.svc.cluster.local)
resource "kubernetes_service_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    selector = { "app.kubernetes.io/name" = var.name }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }
}

# HTTPRoute: Gateway 의 어느 경로/호스트를 이 Service 로 보낼지 (AWS ALB 리스너 규칙)
#   *.localhost(사무실 Mac, http) 와 공개 도메인(Cloudflare 터널, https)을 다른 HTTPRoute 로 나눈다.
#   Envoy 는 X-Forwarded-Proto 를 자기 연결(http) 기준으로 덮어쓰므로, 공개 도메인 쪽만 https 로 고정해
#   앱(Spring forward-headers, OAuth2 redirect_uri 등)이 원래 https 였다는 걸 알게 한다.
#   hostnames 가 비어 있으면(prd catch-all) 기존처럼 하나만.
locals {
  route_hosts_public      = var.route == null ? [] : [for h in var.route.hostnames : h if !endswith(h, ".localhost")]
  route_hosts_local       = var.route == null ? [] : [for h in var.route.hostnames : h if endswith(h, ".localhost")]
  route_split             = length(local.route_hosts_public) > 0 && length(local.route_hosts_local) > 0
  route_path              = var.route == null ? "/" : var.route.path
  route_backend           = [{ name = kubernetes_service_v1.this.metadata[0].name, port = 80 }]
  actuator_redirect       = { type = "RequestRedirect", requestRedirect = { path = { type = "ReplaceFullPath", replaceFullPath = "/" }, statusCode = 302 } }
  force_https             = { type = "RequestHeaderModifier", requestHeaderModifier = { set = [{ name = "X-Forwarded-Proto", value = "https" }] } }
  actuator_redirect_https = { type = "RequestRedirect", requestRedirect = { scheme = "https", path = { type = "ReplaceFullPath", replaceFullPath = "/" }, statusCode = 302 } }
  route_rules = [
    { matches = [{ path = { type = "PathPrefix", value = "/actuator" } }], filters = [local.actuator_redirect] },
    { matches = [{ path = { type = "PathPrefix", value = local.route_path } }], backendRefs = local.route_backend },
  ]
  route_rules_public = [
    { matches = [{ path = { type = "PathPrefix", value = "/actuator" } }], filters = [local.actuator_redirect_https] },
    { matches = [{ path = { type = "PathPrefix", value = local.route_path } }], filters = [local.force_https], backendRefs = local.route_backend },
  ]
}

resource "kubectl_manifest" "route" {
  count = var.route == null ? 0 : 1

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata   = { name = var.name, namespace = var.namespace, labels = local.labels }
    spec = merge(
      {
        parentRefs = [{ name = var.gateway.name, namespace = var.gateway.namespace }]
        rules      = local.route_rules
      },
      # 나눌 때는 localhost 만, 아니면 전체(빈 목록 = catch-all)
      local.route_split ? { hostnames = local.route_hosts_local } : (length(var.route.hostnames) > 0 ? { hostnames = var.route.hostnames } : {})
    )
  })
}

resource "kubectl_manifest" "route_public" {
  count = local.route_split ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata   = { name = "${var.name}-public", namespace = var.namespace, labels = local.labels }
    spec = {
      parentRefs = [{ name = var.gateway.name, namespace = var.gateway.namespace }]
      hostnames  = local.route_hosts_public
      rules      = local.route_rules_public
    }
  })
}
