# 06. CI/CD — 브랜치 전략과 배포

## 저장소

| 저장소 | 공개 | 내용 | 기본 브랜치 |
|--------|------|------|-------------|
| [claudharmony-homepage](https://github.com/ParkSeWoo/claudharmony-homepage) | private | 앱 코드 (Spring Boot), 앱 배포 워크플로 | `develop` |
| [claudharmony-infra](https://github.com/ParkSeWoo/claudharmony-infra) | public | Terraform (클러스터/게이트웨이/환경), 배포 기록, 문서 | `main` |

## 앱 브랜치 전략

```mermaid
gitGraph
    commit id: "init"
    branch develop
    checkout develop
    branch feature/login
    commit id: "작업"
    checkout develop
    merge feature/login id: "PR merge → dev 자동 배포"
    branch release/20261024
    commit id: "QA 수정"
    checkout main
    merge release/20261024 id: "prd 검증 후 merge"
    checkout develop
    merge main id: "back-merge"
```

| 브랜치 | 용도 | 배포 |
|--------|------|------|
| `feature/*` | 기능 개발 | PR 시 CI 빌드 검증만 |
| `develop` | 통합 | **push/merge 하면 dev 자동 배포** |
| `release/YYYYMMDD` | 운영 배포 후보 | **Actions 에서 "Deploy prd" 수동 실행 → prd** |
| `main` | 운영에 나간 코드 | prd 검증 끝난 release 를 merge (배포 트리거 없음) |

### 운영 배포 절차

```bash
cd ~/workspace/claudharmony-homepage
git checkout develop && git pull
git checkout -b release/20261024 && git push -u origin release/20261024

# GitHub → claudharmony-homepage → Actions → "Deploy prd" → Run workflow
#   → Branch: release/20261024 → Run
# (CLI: gh workflow run deploy-prd.yml --ref release/20261024)

# 운영 확인 (curl http://localhost/version, 터널 주소) 후
gh pr create --base main --head release/20261024 --title "release/20261024"
gh pr merge --merge
git checkout develop && git merge origin/main && git push      # back-merge
```

`release/*` 가 아닌 브랜치에서 "Deploy prd" 를 실행하면 `reject` 잡이 실패시킨다.

## 앱 ↔ 인프라 계약

앱 저장소가 아래를 지키면 인프라 변경 없이 배포된다. 바꿔야 하면 infra 도 함께 수정.

| # | 조건 | 인프라 쪽 위치 |
|---|------|----------------|
| 1 | 루트 `Dockerfile` 로 빌드, 빌드 인자 `APP_VERSION` | 앱 워크플로 `docker build` |
| 2 | 컨테이너 포트 `8080` | `services.auto.tfvars.json` 의 `port` |
| 3 | `/actuator/health/liveness`, `/actuator/health/readiness` 200 | `modules/k8s/app` probe |
| 4 | `/actuator/**` 는 외부 비공개 (Gateway 에서 리다이렉트) | `modules/k8s/app` HTTPRoute |
| 5 | 메모리 512Mi 이내 | `memory_mb` |
| 6 | 서비스 이름 `hello-app`, 이미지 `claudharmony/hello-app` | 워크플로 + 카탈로그 key |
| 7 | `GET /version` → `{env, version}` (배포 확인용) | 문서/점검 |

## 이미지 태그 규칙

| 환경 | 태그 | 예 |
|------|------|----|
| dev | `dev-<커밋 7자리>` | `claudharmony/hello-app:dev-1a2b3c4` |
| prd | `<release 날짜>-<커밋 7자리>` | `claudharmony/hello-app:20261024-1a2b3c4` |

`GET /version` 이 `{"env":"prd","version":"20261024-1a2b3c4"}` 처럼 현재 배포를 알려준다.

## 배포 파이프라인 (앱)

```mermaid
sequenceDiagram
    actor Dev as 개발자
    participant GH as GitHub (homepage)
    participant R as self-hosted runner<br/>(사무실 Mac)
    participant I as GitHub (infra)
    participant K as kind 클러스터

    Dev->>GH: develop 에 push / merge
    GH->>R: deploy-dev 잡 (러너가 GitHub 을 폴링해서 가져감)
    R->>R: docker build -t hello-app:dev-<sha>
    R->>R: infra 클론(~/.claudharmony/infra-deploy) git pull
    R->>K: kind load docker-image
    R->>R: envs/dev/images.auto.tfvars.json 갱신
    R->>K: terraform apply (Deployment 이미지 변경 → 롤링 업데이트)
    R->>K: kubectl rollout status
    R->>I: git push "deploy(dev): hello-app=... [skip ci]"
    R-->>GH: Step summary 에 이미지/터널 주소
```

- **왜 self-hosted runner?** 사무실은 이중 NAT 라 GitHub 이 사무실로 접속할 수 없다. 러너가 **바깥으로** GitHub 에 붙어서 일을 가져가므로 포트포워딩이 필요 없다.
- **왜 배포 기록을 infra 에 커밋?** "지금 prd 에 뭐가 떠 있나" 가 Git 에 남고, 롤백은 그 파일을 이전 커밋으로 되돌리면 된다.

## 인프라 파이프라인

`claudharmony-infra` 의 `main` 에 push(머지)되면 **바뀐 스택을 자동 적용**한다.

| 변경 경로 | 자동 적용 | 비고 |
|-----------|-----------|------|
| `platform/gateway/**` | gateway | |
| `modules/k8s/**`, `envs/dev/**` | dev | gateway 다음 순서로 |
| `envs/prd/**` | ❌ 수동 | Actions → Infra apply → Run workflow → `prd` |
| `platform/cluster/**` | ❌ 수동 | kind 는 재생성 — gateway/dev/prd 도 다시 적용해야 함 |

- prd 인프라 변경은 수동 실행하거나, **다음 prd 앱 배포 때** 함께 적용된다 (`deploy.sh` 가 환경 전체를 apply).
- 배포 기록 커밋(`[skip ci]`)은 이 워크플로를 다시 돌리지 않는다.

## Self-hosted runner

| 항목 | 값 |
|------|----|
| 위치 | `~/.claudharmony/runners/<repo>/` (저장소당 1개) |
| 이름 | `office-mac-claudharmony-infra`, `office-mac-claudharmony-homepage` |
| 라벨 | `self-hosted`, `claudharmony-office` |
| 실행 방식 | launchd 서비스 (`svc.sh`) — 로그인 시 자동 시작 |
| 등록 | `scripts/setup-runner.sh` |

```bash
cd ~/.claudharmony/runners/claudharmony-homepage && ./svc.sh status
gh api repos/ParkSeWoo/claudharmony-homepage/actions/runners --jq '.runners[] | "\(.name) \(.status)"'
```

### 보안

- `claudharmony-infra` 는 **public** 이다. 외부인의 포크 PR 이 이 Mac 에서 코드를 실행하지 못하도록
  **"모든 외부 기여자 워크플로는 승인 필요"** 로 설정했다 (`fork-pr-contributor-approval = all_external_contributors`).
- 워크플로 트리거는 `push`(main) 와 `workflow_dispatch` 만 사용 — `pull_request` 로 self-hosted 러너를 쓰지 않는다.
- 더 안전하게 하려면 infra 저장소를 private 으로 전환 (권장).

## 필요한 GitHub 권한

| 무엇 | 왜 |
|------|----|
| gh 토큰 `workflow` scope | `.github/workflows/*` 파일 push (2026-10-24 `gh auth refresh -s workflow` 로 추가) |
| 러너 계정(이 Mac 의 gh 로그인)이 infra 저장소 push 권한 | 배포 기록 커밋 |
