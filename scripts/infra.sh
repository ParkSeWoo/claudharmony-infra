#!/usr/bin/env bash
# 사용법: scripts/infra.sh [plan|apply|destroy|status|logs <svc>|check] [env=office]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="${1:-plan}"
ENV_NAME="${ENV_NAME:-office}"
TF_DIR="$ROOT/envs/$ENV_NAME"

tf() { terraform -chdir="$TF_DIR" "$@"; }

case "$CMD" in
  init)    tf init -input=false ;;
  plan)    tf init -input=false >/dev/null && tf plan ;;
  apply)   tf init -input=false >/dev/null && tf apply ;;
  destroy) tf destroy ;;
  status)
    docker ps --filter "label=claudharmony.environment=$ENV_NAME" \
      --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    ;;
  logs)    docker logs -f --tail 100 "${2:?서비스 이름 필요}" ;;
  check)
    LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || hostname -I | awk '{print $1}')"
    PUB_IP="$(curl -s --max-time 5 ifconfig.me || echo unknown)"
    echo "localhost : $(curl -s -o /dev/null -w '%{http_code}' http://localhost/)"
    echo "LAN  ($LAN_IP): $(curl -s -o /dev/null -w '%{http_code}' "http://$LAN_IP/")"
    echo "Public IP : $PUB_IP  (외부 접속은 사무실 밖에서 확인: curl http://$PUB_IP:<포워딩포트>/)"
    ;;
  *) echo "unknown command: $CMD"; exit 1 ;;
esac
