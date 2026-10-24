#!/usr/bin/env bash
# 서비스 이미지를 환경에 배포하고, 배포 기록(images.auto.tfvars.json)을 infra 저장소에 커밋한다.
# 사용법: scripts/deploy.sh <dev|prd> <service> <image>
#   예) scripts/deploy.sh dev hello-app claudharmony/hello-app:dev-1a2b3c4
# 앱 저장소의 배포 워크플로(self-hosted runner)가 호출한다. 이미지는 같은 호스트에 이미 빌드돼 있어야 한다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_NAME="${1:?환경 필요: dev | prd}"
SERVICE="${2:?서비스 이름 필요}"
IMAGE="${3:?이미지 필요}"
IMAGES_FILE="$ROOT/envs/$ENV_NAME/images.auto.tfvars.json"

docker image inspect "$IMAGE" >/dev/null || { echo "이미지 없음: $IMAGE"; exit 1; }

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

# 헬스체크 대기
CONTAINER="$ENV_NAME-$SERVICE"
for _ in $(seq 1 30); do
  STATUS="$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo none)"
  [ "$STATUS" = "healthy" ] && break
  sleep 3
done
echo "$CONTAINER: $STATUS"
[ "$STATUS" = "healthy" ] || { docker logs --tail 50 "$CONTAINER"; exit 1; }

# 배포 기록 커밋 ([skip ci]: infra 워크플로 재실행 방지)
if ! git diff --quiet -- "$IMAGES_FILE"; then
  git add "$IMAGES_FILE"
  git -c user.name="claudharmony-deploy" -c user.email="deploy@claudharmony.local" \
    commit --quiet -m "deploy($ENV_NAME): $SERVICE=$IMAGE [skip ci]"
  for _ in 1 2 3; do
    git push --quiet origin HEAD:main && break
    git pull --rebase --quiet origin main
  done
fi

echo "✅ $ENV_NAME/$SERVICE → $IMAGE"
"$ROOT/scripts/infra.sh" "$ENV_NAME" url || true
