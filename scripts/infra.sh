#!/usr/bin/env bash
# 사용법: scripts/infra.sh <stack> <command>
#   stack  : cluster | gateway | dev | prd
#            (cluster/gateway = platform/*, dev/prd = envs/*)
#   command: init | plan | apply | destroy | status | logs <svc> | url | check
#   예) scripts/infra.sh cluster apply     # 1단계: kind 클러스터
#       scripts/infra.sh gateway apply     # 2단계: Envoy Gateway
#       scripts/infra.sh dev apply         # 3단계: dev 워크로드
#       scripts/infra.sh prd url
# CI 에서는 AUTO_APPROVE=1 로 apply 확인 프롬프트를 건너뛴다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_NAME="${1:?stack 필요: cluster | gateway | dev | prd}"
CMD="${2:-plan}"
case "$ENV_NAME" in
  cluster|gateway) TF_DIR="$ROOT/platform/$ENV_NAME" ;;
  *)               TF_DIR="$ROOT/envs/$ENV_NAME" ;;
esac
export KUBECONFIG="${KUBECONFIG_CLAUDHARMONY:-$HOME/.claudharmony/kubeconfig}"
k() { kubectl --context kind-claudharmony "$@"; }
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
    case "$ENV_NAME" in
      cluster) kind get clusters; k get nodes -o wide ;;
      gateway) k get gatewayclass,gateway -A; k -n envoy-gateway-system get pods,svc ;;
      *)       k -n "$ENV_NAME" get deploy,pods,svc,httproute ;;
    esac
    ;;
  logs)    k -n "$ENV_NAME" logs -f --tail 100 "deploy/${3:?서비스 이름 필요 (예: hello-app, tunnel)}" ;;
  url)
    URL="$(k -n "$ENV_NAME" logs deploy/tunnel 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)"
    [ -n "$URL" ] && echo "$URL" || { echo "터널 URL 없음 (scripts/infra.sh $ENV_NAME logs tunnel 확인)" >&2; exit 1; }
    ;;
  check)
    HOST="$([ "$ENV_NAME" = prd ] && echo localhost || echo "$ENV_NAME.localhost")"
    echo "local  : http://$HOST/ -> $(curl -s -o /dev/null -w '%{http_code}' -H "Host: $HOST" http://127.0.0.1/)"
    URL="$("$0" "$ENV_NAME" url 2>/dev/null || true)"
    [ -n "$URL" ] && echo "tunnel : $URL -> $(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL/")" || echo "tunnel : 없음"
    ;;
  *) echo "unknown command: $CMD"; exit 1 ;;
esac
