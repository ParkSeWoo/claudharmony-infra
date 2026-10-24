terraform {
  required_version = ">= 1.6"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6"
    }
  }

  # state 는 저장소 밖(~/.claudharmony/state/<env>.tfstate)에 둔다 — scripts/infra.sh 가 init 시 지정.
  # TODO: 어드민 콘솔 단계에서 원격 state (MinIO/S3 + lock) 로 전환
  backend "local" {}
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}
