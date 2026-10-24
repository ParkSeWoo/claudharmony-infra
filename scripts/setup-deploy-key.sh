#!/usr/bin/env bash
# 러너가 배포 기록(images.auto.tfvars.json)을 claudharmony-infra 에 push 할 수 있도록
# 이 저장소 하나에만 쓰기 권한이 있는 SSH deploy key 를 만들고, 배포용 클론에 연결한다.
# (launchd 로 도는 러너는 gh 의 키체인 인증을 못 읽어서 HTTPS push 가 실패함)
set -euo pipefail

REPO="ParkSeWoo/claudharmony-infra"
KEY="$HOME/.claudharmony/deploy_key"
CLONE="$HOME/.claudharmony/infra-deploy"

[ -f "$KEY" ] || ssh-keygen -t ed25519 -N '' -C "claudharmony-deploy@office-mac" -f "$KEY" -q
chmod 600 "$KEY"

if ! gh api "repos/$REPO/keys" --jq '.[].key' | grep -qF "$(cut -d' ' -f1-2 "$KEY.pub")"; then
  gh api "repos/$REPO/keys" -f title="office-mac deploy (images record)" \
    -f key="$(cat "$KEY.pub")" -F read_only=false --jq '"deploy key 등록: id=\(.id)"'
fi

[ -d "$CLONE/.git" ] || git clone "https://github.com/$REPO.git" "$CLONE"
git -C "$CLONE" remote set-url origin "git@github.com:$REPO.git"
git -C "$CLONE" config core.sshCommand "ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

# 확인: 에이전트/키체인 없이 deploy key 만으로 접근되는지
env -u SSH_AUTH_SOCK git -C "$CLONE" ls-remote origin HEAD >/dev/null && echo "✅ deploy key 로 $REPO 접근 OK"
