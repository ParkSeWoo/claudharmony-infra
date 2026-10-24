#!/usr/bin/env bash
# 사용법: scripts/infra.sh [plan|apply|destroy|status|logs <svc>|check|url] [env=office]
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
    echo "Public IP : $PUB_IP  (이중 NAT — 상위 공유기 포워딩 전에는 외부 접속 불가)"
    echo "Tunnel    : $("$0" url 2>/dev/null || echo 없음)"
    ;;
  url)
    URL="$(docker logs tunnel 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)"
    [ -n "$URL" ] && echo "$URL" || { echo "터널 URL 없음 (docker logs tunnel 확인)" >&2; exit 1; }
    ;;
  *) echo "unknown command: $CMD"; exit 1 ;;
esac
