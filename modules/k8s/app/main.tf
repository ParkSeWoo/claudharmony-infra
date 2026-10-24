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
        labels = local.labels
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
                  name = env.value.secret
                  key  = env.value.key
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
resource "kubectl_manifest" "route" {
  count = var.route == null ? 0 : 1

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata   = { name = var.name, namespace = var.namespace, labels = local.labels }
    spec = merge(
      {
        parentRefs = [{ name = var.gateway.name, namespace = var.gateway.namespace }]
        rules = [
          {
            matches = [{ path = { type = "PathPrefix", value = "/actuator" } }]
            filters = [{ type = "RequestRedirect", requestRedirect = { path = { type = "ReplaceFullPath", replaceFullPath = "/" }, statusCode = 302 } }]
          },
          {
            matches     = [{ path = { type = "PathPrefix", value = var.route.path } }]
            backendRefs = [{ name = kubernetes_service_v1.this.metadata[0].name, port = 80 }]
          },
        ]
      },
      length(var.route.hostnames) > 0 ? { hostnames = var.route.hostnames } : {}
    )
  })
}
