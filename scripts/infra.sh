#!/usr/bin/env bash
# 사용법: scripts/infra.sh <stack> <command>
#   stack  : cluster | gateway | edge | addons | dev | prd
#            (cluster/gateway/edge/addons = platform/*, dev/prd = envs/*)
#   command: init | plan | apply | destroy | status | logs <svc> | url | check
#   예) scripts/infra.sh cluster apply     # 1단계: kind 클러스터
#       scripts/infra.sh gateway apply     # 2단계: Envoy Gateway
#       scripts/infra.sh edge apply        # 2.5단계: Cloudflare 터널 + DNS (claudharmony.io)
#       scripts/infra.sh dev apply         # 3단계: dev 워크로드
#       scripts/infra.sh prd url
# CI 에서는 AUTO_APPROVE=1 로 apply 확인 프롬프트를 건너뛴다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_NAME="${1:?stack 필요: cluster | gateway | edge | addons | dev | prd}"
CMD="${2:-plan}"
case "$ENV_NAME" in
  cluster|gateway|edge|addons) TF_DIR="$ROOT/platform/$ENV_NAME" ;;
  *)               TF_DIR="$ROOT/envs/$ENV_NAME" ;;
esac
export KUBECONFIG="${KUBECONFIG_CLAUDHARMONY:-$HOME/.claudharmony/kubeconfig}"
k() { kubectl --context kind-claudharmony "$@"; }

# edge 스택만 Cloudflare 자격증명 필요 (저장소 밖 파일, chmod 600)
if [ "$ENV_NAME" = edge ]; then
  CF_ENV="$HOME/.claudharmony/cloudflare.env"
  [ -r "$CF_ENV" ] || { echo "$CF_ENV 없음 — docs/08-domain.md 참고"; exit 1; }
  set -a; . "$CF_ENV"; set +a
  export TF_VAR_cloudflare_account_id="${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID 비어 있음}"
  : "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN 비어 있음}"   # cloudflare provider 가 환경변수로 읽음
fi
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
  # 여러 서비스 배포가 겹치면 state lock 을 최대 10분 기다린다
  plan)    tf_init && tf plan -input=false -lock-timeout=10m ;;
  apply)   tf_init && tf apply -input=false -lock-timeout=10m $(approve_flag) ;;
  destroy) tf_init && tf destroy $(approve_flag) ;;
  status)
    case "$ENV_NAME" in
      cluster) kind get clusters; k get nodes -o wide ;;
      gateway) k get gatewayclass,gateway -A; k -n envoy-gateway-system get pods,svc ;;
      edge)    k -n edge get deploy,pods ;;
      addons)  k -n kube-system get deploy metrics-server; k top nodes ;;
      *)       k -n "$ENV_NAME" get deploy,pods,svc,httproute ;;
    esac
    ;;
  logs)    k -n "$ENV_NAME" logs -f --tail 100 "deploy/${3:?서비스 이름 필요 (예: hello-app, tunnel)}" ;;
  url)
    # 고정 도메인 (platform/edge). prd = 루트 도메인, dev = dev. 서브도메인
    case "$ENV_NAME" in
      prd) echo "https://claudharmony.io" ;;
      dev) echo "https://dev.claudharmony.io" ;;
      *)   echo "url 은 dev | prd 만 지원" >&2; exit 1 ;;
    esac
    ;;
  check)
    HOST="$([ "$ENV_NAME" = prd ] && echo localhost || echo "$ENV_NAME.localhost")"
    echo "local  : http://$HOST/ -> $(curl -s -o /dev/null -w '%{http_code}' -H "Host: $HOST" http://127.0.0.1/)"
    URL="$("$0" "$ENV_NAME" url)"
    echo "domain : $URL -> $(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL/") $(curl -s --max-time 10 "$URL/version")"
    ;;
  *) echo "unknown command: $CMD"; exit 1 ;;
esac
