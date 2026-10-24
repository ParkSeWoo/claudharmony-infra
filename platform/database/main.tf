# 데이터베이스 Operator — CloudNativePG
#   클러스터에 한 번 설치하면, 각 환경 Namespace 에서 Cluster 리소스(YAML)만 선언해
#   PostgreSQL 생성·장애조치·백업·업그레이드를 Operator 가 처리한다. (AWS RDS 의 "엔진"에 해당)

resource "helm_release" "cnpg" {
  name             = "cnpg"
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  version          = var.cnpg_chart_version
  namespace        = "cnpg-system"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }
  })]
}
