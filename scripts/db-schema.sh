#!/usr/bin/env bash
# DB 스키마 관리 — Atlas (선언형: "테이블이 이렇게 생겨야 한다" 파일 하나 → 차이 계산 → 적용)
#
#   scripts/db-schema.sh <dev|prd> plan  <schema.sql>   # 실제 DB 와 비교해 실행될 SQL 만 보여줌 (변경 없음)
#   scripts/db-schema.sh <dev|prd> apply <schema.sql>   # 적용
#   scripts/db-schema.sh <dev|prd> check <schema.sql>   # 적용할 변경이 남아 있으면 실패 (prd 앱 배포 전 순서 강제용)
#
# 안전장치 (prd)
#   - 위험 변경(DROP TABLE/COLUMN, 타입 변경 등) 은 ALLOW_DESTRUCTIVE=1 없이는 거부
#   - CONFIRM="apply prd" 가 있어야 적용
#   - 적용 직전 pg_dump 백업 → ~/.claudharmony/backups/
# 공통
#   - 앱은 스키마를 바꾸지 않는다. 스키마 적용은 이 단계에서만.
#   - Atlas 가 차이를 계산할 빈 임시 DB(dev-url) 는 로컬 Docker 컨테이너로 띄운다 (PostGIS 포함)
set -euo pipefail

ENV_NAME="${1:?환경 필요: dev | prd}"
CMD="${2:?plan | apply | check}"
SCHEMA="${3:?schema.sql 경로 필요}"
[ -f "$SCHEMA" ] || { echo "스키마 파일 없음: $SCHEMA"; exit 1; }
SCHEMA="$(cd "$(dirname "$SCHEMA")" && pwd)/$(basename "$SCHEMA")"

ATLAS_IMAGE="arigaio/atlas:1.3.3-community"
SCRATCH_IMAGE="imresamu/postgis:18-3.6.1-trixie"   # 공식 postgis 이미지는 arm64 없음
SCRATCH="claudharmony-atlas-dev"
NET="claudharmony-atlas"
case "$ENV_NAME" in dev) PORT=15442 ;; prd) PORT=25442 ;; *) echo "dev | prd"; exit 1 ;; esac

# Atlas 가 관리하지 않는 객체 (PostGIS 시스템 테이블, 과거 Flyway 이력)
EXCLUDES=(--exclude 'spatial_ref_sys' --exclude 'flyway_schema_history' --exclude 'flyway_schema_history.*')

K="kubectl --kubeconfig $HOME/.claudharmony/kubeconfig --context kind-claudharmony -n $ENV_NAME"

# ── 1. 임시 DB (차이 계산용, 재사용) ──
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
if [ "$(docker inspect -f '{{.State.Running}}' "$SCRATCH" 2>/dev/null)" != "true" ]; then
  docker rm -f "$SCRATCH" >/dev/null 2>&1 || true
  docker run -d --name "$SCRATCH" --network "$NET" -e POSTGRES_PASSWORD=dev -e POSTGRES_DB=dev \
    --label claudharmony.purpose=atlas-dev-db "$SCRATCH_IMAGE" >/dev/null
  for _ in $(seq 1 30); do docker exec "$SCRATCH" pg_isready -U postgres -d dev >/dev/null 2>&1 && break; sleep 1; done
  docker exec "$SCRATCH" psql -U postgres -d dev -qc 'CREATE EXTENSION IF NOT EXISTS postgis' >/dev/null
fi
DEV_URL="postgres://postgres:dev@$SCRATCH:5432/dev?sslmode=disable&search_path=public"

# ── 2. 대상 DB 연결 (port-forward, 앱 계정 = 스키마 소유자) ──
DB_USER="$($K get secret pg-app -o jsonpath='{.data.username}' | base64 -d)"
DB_PASS="$($K get secret pg-app -o jsonpath='{.data.password}' | base64 -d)"
$K port-forward svc/pg-rw "$PORT:5432" >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do nc -z 127.0.0.1 "$PORT" 2>/dev/null && break; sleep 0.5; done
TARGET_URL="postgres://$DB_USER:$DB_PASS@host.docker.internal:$PORT/claudharmony?sslmode=disable&search_path=public"

atlas() {
  docker run --rm --network "$NET" --add-host host.docker.internal:host-gateway \
    -v "$SCHEMA:/schema.sql:ro" "$ATLAS_IMAGE" "$@" 2>&1 | grep -vE '^(Notice:|This Atlas edition|testing, down|triggers, and|To install|	curl|Or, visit|	https://atlasgo|$)' || true
}

# ── 3. 계획 (항상 먼저) ──
PLAN="$(atlas schema apply -u "$TARGET_URL" --to file:///schema.sql --dev-url "$DEV_URL" "${EXCLUDES[@]}" --dry-run)"
echo "────────── $ENV_NAME 스키마 계획 ──────────"
echo "$PLAN"
echo "──────────────────────────────────────────"

if echo "$PLAN" | grep -qiE 'error|failed'; then
  echo "❌ 계획 실패"; exit 1
fi
if echo "$PLAN" | grep -q 'Schema is synced'; then
  echo "✅ 변경 없음"; exit 0
fi

DESTRUCTIVE="$(echo "$PLAN" | grep -iE 'DROP (TABLE|COLUMN|SCHEMA)|ALTER COLUMN .* TYPE|TRUNCATE' || true)"
if [ -n "$DESTRUCTIVE" ]; then
  echo "⚠️  위험 변경 감지 (데이터 손실 가능):"
  echo "$DESTRUCTIVE" | sed 's/^/     /'
fi

[ "$CMD" = plan ] && exit 0
if [ "$CMD" = check ]; then
  echo "::error::$ENV_NAME 에 적용되지 않은 스키마 변경이 있습니다 — 먼저 'DB schema $ENV_NAME' 을 실행하세요"
  exit 3
fi
[ "$CMD" = apply ] || { echo "plan | apply | check"; exit 1; }

# ── 4. 적용 ──
if [ "$ENV_NAME" = prd ]; then
  [ -z "$DESTRUCTIVE" ] || [ "${ALLOW_DESTRUCTIVE:-0}" = 1 ] || { echo "❌ prd 위험 변경은 ALLOW_DESTRUCTIVE=1 필요"; exit 1; }
  [ "${CONFIRM:-}" = "apply prd" ] || { echo "❌ prd 적용은 CONFIRM=\"apply prd\" 필요"; exit 1; }
  BK_DIR="$HOME/.claudharmony/backups"; mkdir -p "$BK_DIR"; chmod 700 "$BK_DIR"
  BK="$BK_DIR/prd-$(date +%Y%m%d-%H%M%S).dump"
  $K exec pg-1 -c postgres -- pg_dump -U postgres -Fc claudharmony > "$BK"
  echo "💾 백업: $BK ($(du -h "$BK" | cut -f1))"
fi

atlas schema apply -u "$TARGET_URL" --to file:///schema.sql --dev-url "$DEV_URL" "${EXCLUDES[@]}" --auto-approve
echo "✅ $ENV_NAME 스키마 적용 완료"
