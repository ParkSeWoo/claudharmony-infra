locals {
  namespace = "envoy-gateway-system"
}

# ① 컨트롤러: Envoy Gateway (Gateway API CRD + 컨트롤러 설치)
resource "helm_release" "envoy_gateway" {
  name             = "eg"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = var.envoy_gateway_version
  namespace        = local.namespace
  create_namespace = true
  wait             = true
  timeout          = 600
}

# ② 데이터플레인 설정: Envoy 를 NodePort 로 노출 (kind 에는 LoadBalancer 가 없음)
resource "kubectl_manifest" "envoy_proxy" {
  yaml_body = yamlencode({
    apiVersion = "gateway.envoyproxy.io/v1alpha1"
    kind       = "EnvoyProxy"
    metadata   = { name = "nodeport", namespace = local.namespace }
    spec = {
      provider = {
        type = "Kubernetes"
        kubernetes = {
          envoyService = {
            name = "claudharmony-gateway"
            type = "NodePort"
            # 기본값 Local 은 Envoy Pod 가 없는 노드로 온 트래픽을 버린다.
            # kind 는 호스트 포트가 control-plane 노드에만 연결되므로 Cluster 로 노드 간 전달 허용
            externalTrafficPolicy = "Cluster"
            patch = {
              type  = "StrategicMerge"
              value = { spec = { ports = [{ port = 80, nodePort = var.node_port }] } }
            }
          }
        }
      }
    }
  })
  depends_on = [helm_release.envoy_gateway]
}

# ③ GatewayClass: "이 클러스터의 L7 로드밸런서 종류" (AWS 의 ALB 타입 선택에 해당)
resource "kubectl_manifest" "gateway_class" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata   = { name = "claudharmony" }
    spec = {
      controllerName = "gateway.envoyproxy.io/gatewayclass-controller"
      parametersRef = {
        group     = "gateway.envoyproxy.io"
        kind      = "EnvoyProxy"
        name      = "nodeport"
        namespace = local.namespace
      }
    }
  })
  depends_on = [kubectl_manifest.envoy_proxy]
}

# ④ Gateway: 실제 리스너 (AWS ALB 의 리스너 :80 에 해당)
#    라벨 claudharmony.io/gateway-access=true 가 붙은 Namespace 의 HTTPRoute 만 붙을 수 있다.
resource "kubectl_manifest" "gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata   = { name = "claudharmony", namespace = local.namespace }
    spec = {
      gatewayClassName = "claudharmony"
      listeners = [{
        name     = "http"
        protocol = "HTTP"
        port     = 80
        allowedRoutes = {
          namespaces = {
            from     = "Selector"
            selector = { matchLabels = { "claudharmony.io/gateway-access" = "true" } }
          }
        }
      }]
    }
  })
  wait       = true
  depends_on = [kubectl_manifest.gateway_class]
}
