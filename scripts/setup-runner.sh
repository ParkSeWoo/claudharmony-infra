#!/usr/bin/env bash
# 사무실 Mac 에 GitHub Actions self-hosted runner 를 등록하고 서비스(launchd)로 띄운다.
# 사용법: scripts/setup-runner.sh [repo ...]   (기본: claudharmony-infra web api console)
# 필요: gh 로그인(repo 권한), 이 Mac 의 docker / terraform
set -euo pipefail

OWNER="ParkSeWoo"
if [ $# -eq 0 ]; then
  REPOS=(claudharmony-infra claudharmony-web claudharmony-api claudharmony-console)
else
  REPOS=("$@")
fi
LABEL="claudharmony-office"
BASE="$HOME/.claudharmony/runners"
VERSION="$(gh api repos/actions/runner/releases/latest --jq .tag_name | sed 's/^v//')"
PKG="$HOME/.claudharmony/runner-pkg/actions-runner-osx-arm64-$VERSION.tar.gz"

mkdir -p "$(dirname "$PKG")"
[ -f "$PKG" ] || curl -fsSL -o "$PKG" \
  "https://github.com/actions/runner/releases/download/v$VERSION/actions-runner-osx-arm64-$VERSION.tar.gz"

for REPO in "${REPOS[@]}"; do
  DIR="$BASE/$REPO"
  echo "== $REPO → $DIR"
  mkdir -p "$DIR" && cd "$DIR"
  [ -f config.sh ] || tar xzf "$PKG"

  TOKEN="$(gh api -X POST "repos/$OWNER/$REPO/actions/runners/registration-token" --jq .token)"
  ./config.sh --unattended --replace \
    --url "https://github.com/$OWNER/$REPO" --token "$TOKEN" \
    --name "office-mac-$REPO" --labels "$LABEL" --work _work

  ./svc.sh install || true
  ./svc.sh start
done

echo
for REPO in "${REPOS[@]}"; do
  gh api "repos/$OWNER/$REPO/actions/runners" --jq '.runners[] | "\(.name)\t\(.status)"'
done
