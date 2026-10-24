#!/usr/bin/env bash
# 로컬에서 클러스터 PostgreSQL 확인하기 (dev / prd)
#
#   scripts/db.sh up                 # dev·prd 상시 연결 (127.0.0.1 전용 프록시 컨테이너, 재부팅 후에도 자동 시작)
#   scripts/db.sh status             # 연결 상태
#   scripts/db.sh down               # 연결 끊기
#   scripts/db.sh info [env] [role]  # 접속 정보 표 (비밀번호는 가림, --show 로 표시, --copy 로 클립보드)
#   scripts/db.sh psql <env> [role]  # psql 접속 (up 안 돼 있으면 자동으로 올림)
#   scripts/db.sh pgpass             # ~/.pgpass 생성 → psql·pg_dump 비밀번호 입력 생략 (prd 쓰기 계정 제외)
#   scripts/db.sh <env> [role]       # (예전 방식) 포그라운드 port-forward + 비밀번호 클립보드
#
#   env : dev | prd          role: readonly(기본) | app
#   포트: dev 127.0.0.1:15432 / prd 127.0.0.1:25432, DB: claudharmony
#   readonly 를 기본으로 — 실수로 데이터를 바꾸지 않게. prd 의 app(쓰기) 계정은 명시해야만.
set -euo pipefail

DB=claudharmony
PROXY_IMAGE="alpine/socat:1.8.1.1"

k() { kubectl --kubeconfig "$HOME/.claudharmony/kubeconfig" --context kind-claudharmony "$@"; }
port_of() { case "$1" in dev) echo 15432 ;; prd) echo 25432 ;; *) echo "환경: dev | prd" >&2; exit 1 ;; esac; }
# 클러스터 안 NodePort (modules/k8s/postgres local_node_port) — kind Docker 네트워크에서만 닿는다
nodeport_of() { case "$1" in dev) echo 31432 ;; prd) echo 32432 ;; esac; }
secret_of() { case "$1" in app) echo pg-app ;; readonly) echo pg-readonly ;; *) echo "역할: readonly | app" >&2; exit 1 ;; esac; }
field() { k -n "$1" get secret "$(secret_of "$2")" -o jsonpath="{.data.$3}" | base64 -d; }
psql_bin() { command -v psql || echo /opt/homebrew/opt/libpq/bin/psql; }
# 포트가 열려 있는지만 본다
is_up() { lsof -nP -iTCP:"$(port_of "$1")" -sTCP:LISTEN >/dev/null 2>&1; }

# kubectl port-forward 는 클라이언트가 접속을 끊을 때 DB 쪽 리셋으로 프로세스가 종료된다(lost connection to pod).
# 대신 kind 네트워크 안의 NodePort 로 넘겨주는 socat 컨테이너를 127.0.0.1 에만 열어 둔다.
up_one() {
  local env="$1" name="claudharmony-pg-$1"
  if [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = true ]; then return; fi
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run -d --name "$name" --restart unless-stopped --network kind \
    -p "127.0.0.1:$(port_of "$env"):5432" --label claudharmony.purpose=local-db-access \
    "$PROXY_IMAGE" "TCP-LISTEN:5432,fork,reuseaddr" "TCP:claudharmony-control-plane:$(nodeport_of "$env")" >/dev/null
  for _ in $(seq 1 20); do is_up "$env" && break; sleep 0.5; done
}

down_one() {
  docker rm -f "claudharmony-pg-$1" >/dev/null 2>&1 || true
}

status() {
  printf '%-5s %-17s %s\n' 환경 주소 상태
  for env in dev prd; do
    local s="꺼짐"
    is_up "$env" && s="연결됨 ($(k -n "$env" get cluster pg -o jsonpath='{.status.phase}' 2>/dev/null))"
    printf '%-5s %-17s %s\n' "$env" "127.0.0.1:$(port_of "$env")" "$s"
  done
}

info() {
  local envs=("dev" "prd") roles=("readonly" "app") show=0 copy=0 args=()
  for a in "$@"; do case "$a" in --show) show=1 ;; --copy) copy=1 ;; *) args+=("$a") ;; esac; done
  [ "${#args[@]}" -ge 1 ] && envs=("${args[0]}")
  [ "${#args[@]}" -ge 2 ] && roles=("${args[1]}")
  echo "PostgreSQL 18 + PostGIS · DB: $DB · SSL: 끔 (port-forward 로 로컬만)"
  printf '%-4s %-9s %-16s %-10s %s\n' 환경 역할 호스트:포트 사용자 비밀번호
  for env in "${envs[@]}"; do
    for role in "${roles[@]}"; do
      local user pass shown
      user="$(field "$env" "$role" username)"; pass="$(field "$env" "$role" password)"
      shown="$( [ $show = 1 ] && echo "$pass" || echo "${pass:0:3}•••••• (--show 로 표시)")"
      printf '%-4s %-9s %-16s %-10s %s\n' "$env" "$role" "127.0.0.1:$(port_of "$env")" "$user" "$shown"
      if [ $copy = 1 ]; then printf '%s' "$pass" | pbcopy; echo "     ↳ $env/$role 비밀번호 클립보드에 복사"; fi
    done
  done
  echo
  echo "URL 형식: postgresql://<사용자>@127.0.0.1:<포트>/$DB   (연결 전: scripts/db.sh up)"
}

pgpass() {
  local f="$HOME/.pgpass" tmp
  tmp="$(mktemp)"
  if [ -f "$f" ]; then grep -vE '^127\.0\.0\.1:(15432|25432):' "$f" > "$tmp" || true; fi
  {
    echo "127.0.0.1:15432:$DB:$(field dev readonly username):$(field dev readonly password)"
    echo "127.0.0.1:15432:$DB:$(field dev app username):$(field dev app password)"
    echo "127.0.0.1:25432:$DB:$(field prd readonly username):$(field prd readonly password)"
    # prd app(쓰기) 계정은 일부러 넣지 않는다
  } >> "$tmp"
  install -m 600 "$tmp" "$f"; rm -f "$tmp"
  echo "~/.pgpass 갱신 (600): dev readonly·app, prd readonly — prd 쓰기 계정은 제외"
}

run_psql() {
  local env="${1:?dev | prd}" role="${2:-readonly}"
  is_up "$env" || up_one "$env"
  PGPASSWORD="$(field "$env" "$role" password)" exec "$(psql_bin)" \
    -h 127.0.0.1 -p "$(port_of "$env")" -U "$(field "$env" "$role" username)" -d "$DB" \
    -v PROMPT1="[$env/$role] %/%R%# "
}

legacy() {
  local env="$1" role="${2:-readonly}"
  field "$env" "$role" password | pbcopy
  info "$env" "$role"
  echo "비밀번호 클립보드에 복사됨 · Ctrl+C 로 종료"
  exec kubectl --kubeconfig "$HOME/.claudharmony/kubeconfig" --context kind-claudharmony \
    -n "$env" port-forward svc/pg-rw "$(port_of "$env"):5432"
}

case "${1:-status}" in
  up)     up_one dev; up_one prd; status ;;
  down)   down_one dev; down_one prd; status ;;
  status) status ;;
  info)   shift; info "$@" ;;
  psql)   shift; run_psql "$@" ;;
  pgpass) pgpass ;;
  dev|prd) legacy "$@" ;;
  -h|--help|help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "알 수 없는 명령: $1 (scripts/db.sh help)"; exit 1 ;;
esac
