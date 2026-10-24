locals {
  kubeconfig = pathexpand(var.kubeconfig_path)
  kind_config = templatefile("${path.module}/kind-config.yaml.tftpl", {
    cluster_name   = var.cluster_name
    node_image     = var.node_image
    workers        = var.workers
    http_host_port = var.http_host_port
  })
}

resource "local_file" "kind_config" {
  filename = "${path.module}/.generated/kind-config.yaml"
  content  = local.kind_config
}

# 클러스터 설정이 바뀌면 재생성 (kind 는 생성 후 노드 구성 변경 불가)
resource "terraform_data" "cluster" {
  triggers_replace = [sha1(local.kind_config)]

  input = {
    name       = var.cluster_name
    kubeconfig = local.kubeconfig
    config     = local_file.kind_config.filename
  }

  provisioner "local-exec" {
    command = "kind create cluster --config '${self.input.config}' --kubeconfig '${self.input.kubeconfig}' --wait 180s"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kind delete cluster --name '${self.input.name}' --kubeconfig '${self.input.kubeconfig}'"
  }
}
