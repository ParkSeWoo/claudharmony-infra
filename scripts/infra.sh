#!/usr/bin/env bash
# 사용법: scripts/infra.sh <dev|prd> <init|plan|apply|destroy|status|logs <svc>|url|check>
#   예) scripts/infra.sh dev plan
#       scripts/infra.sh prd url
# CI 에서는 AUTO_APPROVE=1 로 apply 확인 프롬프트를 건너뛴다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_NAME="${1:?환경 필요: dev | prd}"
CMD="${2:-plan}"
TF_DIR="$ROOT/envs/$ENV_NAME"
STATE_DIR="${CLAUDHARMONY_STATE_DIR:-$HOME/.claudharmony/state}"

[ -d "$TF_DIR" ] || { echo "unknown env: $ENV_NAME"; exit 1; }

tf() { terraform -chdir="$TF_DIR" "$@"; }
tf_init() {
  mkdir -p "$STATE_DIR"
  tf init -input=false -reconfigure -backend-config="path=$STATE_DIR/$ENV_NAME.tfstate" >/dev/null
}
approve_flag() { [ "${AUTO_APPROVE:-0}" = "1" ] && echo "-auto-approve" || true; }

case "$CMD" in
  init)    tf_init ;;
  plan)    tf_init && tf plan -input=false ;;
  apply)   tf_init && tf apply -input=false $(approve_flag) ;;
  destroy) tf_init && tf destroy $(approve_flag) ;;
  status)
    docker ps --filter "label=claudharmony.environment=$ENV_NAME" \
      --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    ;;
  logs)    docker logs -f --tail 100 "$ENV_NAME-${3:?서비스 이름 필요 (예: hello-app, nginx, tunnel)}" ;;
  url)
    URL="$(docker logs "$ENV_NAME-tunnel" 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)"
    [ -n "$URL" ] && echo "$URL" || { echo "터널 URL 없음 (docker logs $ENV_NAME-tunnel 확인)" >&2; exit 1; }
    ;;
  check)
    PORT="$(tf_init && tf output -json stack | python3 -c 'import sys,json;print(json.load(sys.stdin)["local_url"])')"
    echo "local  : $PORT -> $(curl -s -o /dev/null -w '%{http_code}' "$PORT/")"
    URL="$("$0" "$ENV_NAME" url 2>/dev/null || true)"
    [ -n "$URL" ] && echo "tunnel : $URL -> $(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL/")" || echo "tunnel : 없음"
    ;;
  *) echo "unknown command: $CMD"; exit 1 ;;
esac
