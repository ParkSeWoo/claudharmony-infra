#!/usr/bin/env bash
# 클러스터 안 PostgreSQL 에 로컬 DB 툴(TablePlus / DBeaver / DataGrip / psql)로 접속하기
#   scripts/db.sh <dev|prd> [app|readonly]      (기본 readonly — 실수로 데이터 바꾸지 않게)
# port-forward 를 열고 접속 정보를 보여준다. 비밀번호는 화면에 찍지 않고 클립보드로 복사.
# 종료: Ctrl+C
set -euo pipefail

ENV_NAME="${1:?환경 필요: dev | prd}"
ROLE="${2:-readonly}"
case "$ENV_NAME" in dev) PORT=15432 ;; prd) PORT=25432 ;; *) echo "dev | prd"; exit 1 ;; esac
case "$ROLE" in app) SECRET=pg-app ;; readonly) SECRET=pg-readonly ;; *) echo "app | readonly"; exit 1 ;; esac

K="kubectl --kubeconfig $HOME/.claudharmony/kubeconfig --context kind-claudharmony -n $ENV_NAME"
USER_NAME="$($K get secret "$SECRET" -o jsonpath='{.data.username}' | base64 -d)"
$K get secret "$SECRET" -o jsonpath='{.data.password}' | base64 -d | pbcopy

cat <<INFO
────────────────────────────────────────────
 $ENV_NAME PostgreSQL  ($ROLE)
   Host     : 127.0.0.1
   Port     : $PORT
   Database : claudharmony
   User     : $USER_NAME
   Password : (클립보드에 복사됨 — DB 툴에 붙여넣기)
   SSL      : 끔 (port-forward 로 로컬만 연결)

 psql: PGPASSWORD=\$(pbpaste) psql -h 127.0.0.1 -p $PORT -U $USER_NAME claudharmony
────────────────────────────────────────────
 Ctrl+C 로 종료
INFO
exec $K port-forward svc/pg-rw "$PORT:5432"
