#!/usr/bin/env bash
# 서비스 이미지를 환경에 배포하고, 배포 기록(images.auto.tfvars.json)을 infra 저장소에 커밋한다.
# 사용법: scripts/deploy.sh <dev|prd|console|identity> <service> <image>
#   예) scripts/deploy.sh dev api claudharmony/api:dev-1a2b3c4
#       scripts/deploy.sh identity keycloak claudharmony/keycloak:20261024-1a2b3c4   (platform/identity, 하나뿐인 Keycloak — dev·prd realm 공용)
# 앱 저장소의 배포 워크플로(self-hosted runner)가 호출한다.
# 이미지는 같은 호스트에 빌드돼 있어야 하고, 여기서 kind 클러스터 노드로 load 한다 (레지스트리 대신).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_NAME="${1:?환경 필요: dev | prd | console | identity}"
SERVICE="${2:?서비스 이름 필요}"
IMAGE="${3:?이미지 필요}"
case "$ENV_NAME" in
  identity) IMAGES_FILE="$ROOT/platform/identity/images.auto.tfvars.json" ;;   # Namespace = identity
  *)        IMAGES_FILE="$ROOT/envs/$ENV_NAME/images.auto.tfvars.json" ;;      # Namespace = 환경 이름
esac

docker image inspect "$IMAGE" >/dev/null || { echo "이미지 없음: $IMAGE"; exit 1; }

# 배포 직렬화: 여러 저장소(api, web ...)의 러너가 같은 infra 클론/state 를 동시에 쓰지 않도록
# (macOS 에는 flock 이 없어 mkdir 의 원자성으로 잠금. 최대 10분 대기)
LOCK="$HOME/.claudharmony/deploy.lock"
GOT_LOCK=0
for i in $(seq 1 120); do
  if mkdir "$LOCK" 2>/dev/null; then GOT_LOCK=1; break; fi
  [ "$i" = 1 ] && echo "다른 배포 진행 중 — 대기: $(cat "$LOCK/owner" 2>/dev/null)"
  sleep 5
done
[ "$GOT_LOCK" = 1 ] || { echo "::error::배포 잠금 대기 시간 초과 ($LOCK) — 멈춘 배포가 없으면 디렉토리 삭제"; exit 1; }
echo "$$ $ENV_NAME/$SERVICE $(date '+%F %T')" > "$LOCK/owner"
trap 'rm -rf "$LOCK"' EXIT
kind load docker-image "$IMAGE" --name "${KIND_CLUSTER:-claudharmony}"

cd "$ROOT"
git pull --rebase --quiet origin main

python3 - "$IMAGES_FILE" "$SERVICE" "$IMAGE" <<'PY'
import json, sys
path, svc, img = sys.argv[1:]
data = json.load(open(path))
data.setdefault("images", {})[svc] = img
json.dump(data, open(path, "w"), indent=2, sort_keys=True)
open(path, "a").write("\n")
PY

AUTO_APPROVE=1 "$ROOT/scripts/infra.sh" "$ENV_NAME" apply

# 롤아웃 확인 (terraform 이 wait_for_rollout 으로 이미 기다리지만, 결과를 로그에 남긴다)
kubectl --kubeconfig "$HOME/.claudharmony/kubeconfig" --context kind-claudharmony \
  -n "$ENV_NAME" rollout status "deploy/$SERVICE" --timeout=180s

# 배포 기록 커밋 ([skip ci]: infra 워크플로 재실행 방지)
if ! git diff --quiet -- "$IMAGES_FILE"; then
  git add "$IMAGES_FILE"
  git -c user.name="claudharmony-deploy" -c user.email="deploy@claudharmony.local" \
    commit --quiet -m "deploy($ENV_NAME): $SERVICE=$IMAGE [skip ci]"
  PUSHED=0
  for _ in 1 2 3; do
    if git push --quiet origin HEAD:main; then PUSHED=1; break; fi
    git pull --rebase --quiet origin main || true
  done
  # 배포는 끝났지만 기록이 Git 에 안 남으면 이후 apply 가 이전 이미지로 되돌릴 수 있다 → 실패로 알림
  [ "$PUSHED" = 1 ] || { echo "::error::배포 기록 push 실패 — scripts/setup-deploy-key.sh 확인"; exit 1; }
fi

echo "✅ $ENV_NAME/$SERVICE → $IMAGE"
"$ROOT/scripts/infra.sh" "$ENV_NAME" url || true
