# 클러스터 공용 부가 기능 (addons)
#   metrics-server: kubectl top / k9s 의 CPU·MEM / 이후 HPA(자동 확장)의 기반

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version
  namespace  = "kube-system"
  wait       = true

  values = [yamlencode({
    # kind 의 kubelet 인증서는 노드 IP 가 SAN 에 없어서 TLS 검증을 끈다 (로컬 클러스터 한정)
    args = ["--kubelet-insecure-tls"]
    resources = {
      requests = { cpu = "50m", memory = "64Mi" }
      limits   = { memory = "128Mi" }
    }
  })]
}
