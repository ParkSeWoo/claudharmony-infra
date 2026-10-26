#!/usr/bin/env bash
# 사용법: scripts/infra.sh <stack> <command>
#   stack  : cluster | gateway | edge | addons | database | identity | realms | dev | prd | console
#            (cluster/gateway/edge/addons/database/identity/realms = platform/*, dev/prd/console = envs/*)
#   command: init | plan | apply | destroy | status | logs <svc> | url | check
#   예) scripts/infra.sh cluster apply     # 1단계: kind 클러스터
#       scripts/infra.sh gateway apply     # 2단계: Envoy Gateway
#       scripts/infra.sh edge apply        # 2.5단계: Cloudflare 터널 + DNS (claudharmony.io)
#       scripts/infra.sh identity apply    # 인증 서버 Keycloak
#       scripts/infra.sh realms apply      # Keycloak realm·client·계정 (Keycloak provider)
#       scripts/infra.sh dev apply         # 3단계: dev 워크로드
#       scripts/infra.sh prd url
# CI 에서는 AUTO_APPROVE=1 로 apply 확인 프롬프트를 건너뛴다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_NAME="${1:?stack 필요: cluster | gateway | edge | addons | database | identity | realms | dev | prd | console}"
CMD="${2:-plan}"
case "$ENV_NAME" in
  cluster|gateway|edge|addons|database|identity|realms) TF_DIR="$ROOT/platform/$ENV_NAME" ;;
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
  # 콘솔 로그인 허용 이메일 (공개 저장소에 두지 않음) → JSON 배열
  TF_VAR_console_allowed_emails="$(python3 -c 'import json,os;print(json.dumps([e.strip() for e in os.environ.get("CONSOLE_ALLOWED_EMAILS","").split(",") if e.strip()]))')"
  export TF_VAR_console_allowed_emails
fi
# realms 스택은 Keycloak 관리 API 를 직접 부른다. *.localhost 는 브라우저만 풀어 주므로
# 실행하는 동안만 Service 로 port-forward 하고, 첫 기동 때 만든 bootstrap client 로 인증한다.
if [ "$ENV_NAME" = realms ] && [[ "${2:-plan}" =~ ^(plan|apply|destroy)$ ]]; then
  KC_PORT=18080
  k -n identity port-forward svc/keycloak "$KC_PORT:80" >/dev/null 2>&1 &
  KC_PF=$!
  trap 'kill $KC_PF 2>/dev/null || true' EXIT
  for _ in $(seq 1 20); do nc -z 127.0.0.1 "$KC_PORT" 2>/dev/null && break; sleep 0.5; done
  export TF_VAR_keycloak_url="http://127.0.0.1:$KC_PORT"
  TF_VAR_keycloak_client_secret="$(k -n identity get secret keycloak-bootstrap -o jsonpath='{.data.client-secret}' | base64 -d)"
  export TF_VAR_keycloak_client_secret
  # 소셜 로그인 키 (저장소 밖, chmod 600) — GOOGLE_/GITHUB_/KAKAO_/NAVER_ CLIENT_ID·CLIENT_SECRET. 없으면 소셜 로그인 없음
  ID_ENV="$HOME/.claudharmony/identity.env"
  if [ -r "$ID_ENV" ]; then set -a; . "$ID_ENV"; set +a; fi
  TF_VAR_social="$(python3 -c 'import json,os
print(json.dumps({n:{"client_id":os.environ[f"{n.upper()}_CLIENT_ID"],"client_secret":os.environ.get(f"{n.upper()}_CLIENT_SECRET","")}
  for n in ("google","github","kakao","naver") if os.environ.get(f"{n.upper()}_CLIENT_ID")}))')"
  export TF_VAR_social
fi
# dev·prd: 외부 서비스 키 (저장소 밖, chmod 600) → Secret app-secrets. 파일 형식: YOUTUBE_API_KEY=...
#   변수 이름을 소문자·하이픈으로 바꿔 Secret 키로 쓴다 (YOUTUBE_API_KEY → youtube-api-key)
if [ "$ENV_NAME" = dev ] || [ "$ENV_NAME" = prd ]; then
  APP_ENV_FILE="$HOME/.claudharmony/app-secrets.env"
  TF_VAR_app_secrets="$(python3 - "$APP_ENV_FILE" <<'PY'
import json, os, sys
out = {}
p = sys.argv[1]
if os.path.exists(p):
    for line in open(p):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            v = v.strip().strip('"').strip("'")
            if v:
                out[k.strip().lower().replace("_", "-")] = v
print(json.dumps(out))
PY
)"
  export TF_VAR_app_secrets
fi
STATE_DIR="${CLAUDHARMONY_STATE_DIR:-$HOME/.claudharmony/state}"

[ -d "$TF_DIR" ] || { echo "unknown env: $ENV_NAME"; exit 1; }

tf() { terraform -chdir="$TF_DIR" "$@"; }
tf_init() {
  mkdir -p "$STATE_DIR"
  tf init -input=false -reconfigure -backend-config="path=$STATE_DIR/$ENV_NAME.tfstate" >/dev/null
}
approve_flag() { [ "${AUTO_APPROVE:-0}" = "1" ] && echo "-auto-approve" || true; }

# 손으로 apply 할 때도 deploy.sh 와 같은 잠금을 잡고, 배포 기록이 원격보다 뒤처졌으면 거부한다.
# (뒤처진 images.auto.tfvars.json 으로 apply 하면 다른 세션·러너가 막 배포한 이미지를 이전 것으로 되돌린다 — 작업 기록 #49)
# deploy.sh 는 이미 잠금을 잡고 기록을 갱신한 뒤 부르므로 CLAUDHARMONY_DEPLOY_LOCKED=1 로 건너뛴다.
guard_images() {
  [ -f "$TF_DIR/images.auto.tfvars.json" ] || return 0
  [ "${CLAUDHARMONY_DEPLOY_LOCKED:-0}" = 1 ] && return 0
  LOCK="$HOME/.claudharmony/deploy.lock"
  for i in $(seq 1 120); do
    mkdir "$LOCK" 2>/dev/null && break
    [ "$i" = 1 ] && echo "배포 진행 중 — 대기: $(cat "$LOCK/owner" 2>/dev/null)"
    [ "$i" = 120 ] && { echo "잠금 대기 시간 초과 ($LOCK)"; exit 1; }
    sleep 5
  done
  echo "$$ manual $ENV_NAME $(date '+%F %T')" > "$LOCK/owner"
  trap 'rm -rf "$LOCK"' EXIT
  git -C "$ROOT" fetch --quiet origin main
  REL="${TF_DIR#"$ROOT"/}/images.auto.tfvars.json"
  if ! git -C "$ROOT" diff --quiet HEAD origin/main -- "$REL"; then
    echo "❌ $REL 가 원격(main)보다 뒤처짐 — 다른 곳에서 배포됨. git pull --rebase 후 다시 실행"
    exit 1
  fi
}

case "$CMD" in
  init)    tf_init ;;
  # 여러 서비스 배포가 겹치면 state lock 을 최대 10분 기다린다
  plan)    tf_init && tf plan -input=false -lock-timeout=10m ;;
  apply)   guard_images && tf_init && tf apply -input=false -lock-timeout=10m $(approve_flag) ;;
  destroy) tf_init && tf destroy $(approve_flag) ;;
  status)
    case "$ENV_NAME" in
      cluster) kind get clusters; k get nodes -o wide ;;
      gateway) k get gatewayclass,gateway -A; k -n envoy-gateway-system get pods,svc ;;
      edge)    k -n edge get deploy,pods ;;
      addons)  k -n kube-system get deploy metrics-server; k top nodes ;;
      database) k -n cnpg-system get deploy,pods; k get clusters.postgresql.cnpg.io -A ;;
      identity|realms) k -n identity get deploy,pods,svc,httproute,clusters.postgresql.cnpg.io ;;
      *)       k -n "$ENV_NAME" get deploy,pods,svc,httproute ;;
    esac
    ;;
  logs)    k -n "$ENV_NAME" logs -f --tail 100 "deploy/${3:?서비스 이름 필요 (예: hello-app, tunnel)}" ;;
  url)
    # 고정 도메인 (platform/edge). prd = 루트 도메인, dev = dev. 서브도메인
    case "$ENV_NAME" in
      prd) echo "https://claudharmony.io" ;;
      dev) echo "https://dev.claudharmony.io" ;;
      console) echo "https://console.claudharmony.io" ;;
      identity|realms) echo "https://auth.claudharmony.io  (관리: http://auth.localhost/admin/)" ;;
      *)   echo "url 은 dev | prd 만 지원" >&2; exit 1 ;;
    esac
    ;;
  check)
    HOST="$([ "$ENV_NAME" = prd ] && echo localhost || echo "$ENV_NAME.localhost")"   # console → console.localhost
    echo "local  : http://$HOST/ -> $(curl -s -o /dev/null -w '%{http_code}' -H "Host: $HOST" http://127.0.0.1/)"
    URL="$("$0" "$ENV_NAME" url)"
    echo "domain : $URL -> $(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL/") $(curl -s --max-time 10 "$URL/version")"
    ;;
  *) echo "unknown command: $CMD"; exit 1 ;;
esac
