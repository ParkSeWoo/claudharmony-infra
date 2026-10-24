# 07. 작업 기록 (Worklog)

모든 작업을 단계별로 기록한다. **새 작업은 맨 위 날짜 섹션 아래에 이어서 추가.**
각 항목: 무엇을 했나 → 결과 → (문제가 있었다면) 원인과 해결 → 배운 점.

---

## 2026-10-24 (토) — 사무실 인프라 1일차

### 진행 상태 요약

| # | 단계 | 상태 |
|---|------|------|
| 1 | 환경 점검 & 저장소 연결 | ✅ |
| 2 | Docker + Terraform 으로 nginx → Spring Boot | ✅ |
| 3 | 모듈 구조 / 서비스 카탈로그 (어드민 콘솔 기반) | ✅ |
| 4 | 문서 (md/html) + Obsidian | ✅ |
| 5 | 외부 접속 시도 — 공유기 포트포워딩 | ⛔ 이중 NAT (상위 공유기 계정 없음) |
| 6 | 외부 접속 — Cloudflare Tunnel | ✅ |
| 7 | dev / prd 환경 분리 + 배포 스크립트 | ✅ |
| 8 | 앱 저장소 분리 (claudharmony-homepage) + 배포 워크플로 | ✅ |
| 9 | Kubernetes v1.37 (kind) + Envoy Gateway 로 전환 | ✅ |
| 10 | 인프라 자동 적용 워크플로 | ✅ (러너 등록 후 동작) |
| 11 | self-hosted runner 등록 | ✅ (사용자 실행) |
| 12 | 파이프라인 E2E — dev | ✅ `dev-c0184f6` 자동 배포 |
| 13 | 파이프라인 E2E — prd | ✅ `20261024-c0184f6` 수동 배포 + 기록 자동 커밋 |

---

### 1. 환경 점검 & 저장소 연결

- 확인: Terraform 1.15.6, Docker Desktop 27.4 (arm64), gh 로그인(ParkSeWoo), Java 25(호스트, 사용 안 함)
- GitHub `ParkSeWoo/claudharmony-infra` 는 빈 public 저장소였음
- 포트 점유 확인: 80 비어 있음, 8080 은 다른 프로젝트(airflow) 사용 중 → 앱 포트를 호스트에 열지 않기로
- `~/infra` 생성, `git init` → push

**문제**: SSH 로 push 실패 (`Please make sure you have the correct access rights`)
**원인**: 이 Mac 의 SSH 키가 GitHub 에 등록 안 됨 (gh 는 protocol=ssh 로 설정돼 있었음)
**해결**: `gh auth setup-git` + 원격 주소를 HTTPS 로 → gh 토큰으로 인증

### 2. Docker + Terraform 으로 nginx → Spring Boot

- Spring Boot 3.5.6 / Java 21, `GET /` → "안녕하세요 클라우드 하모니"
- Dockerfile 멀티스테이지 (`gradle:8.14-jdk21` → `eclipse-temurin:21-jre`) — 호스트에 JDK 불필요
- Terraform `kreuzwerker/docker` provider 로 network / app / nginx 컨테이너

**문제 1**: `fileset(dir, "{Dockerfile,*.gradle,src/**}")` → `syntax error in pattern`
**해결**: 패턴 3개로 나눠 `setunion(fileset(...), ...)`

**문제 2**: `docker_image` build → `Error running legacy build: failed to read downloaded context: ... 403`
**원인**: provider 의 legacy builder 가 Docker Desktop(containerd image store)과 호환 안 됨. `docker build`(BuildKit) 는 정상
**해결**: `terraform_data` + `local-exec docker build` 로 빌드, 이미지 태그 = 소스 해시

**문제 3**: apply 후에도 plan 에 `memory_swap = 1024 -> null` 계속 표시 (드리프트)
**원인**: Docker 가 memory 지정 시 swap 기본값을 채워 넣음
**해결**: 모듈에서 `memory_swap = memory * 2` 명시
**배운 점**: provider 가 기본값을 채우는 속성은 코드에 명시해야 plan 이 깨끗해진다

**문제 4**: 앱 컨테이너를 재생성하면 nginx 가 502 를 낼 위험
**원인**: nginx `upstream` 블록은 시작 시 DNS 를 한 번만 resolve
**해결**: `resolver 127.0.0.11` + `set $upstream ...; proxy_pass http://$upstream;` (요청마다 resolve). `-replace` 로 앱 재생성해서 200 확인

### 3. 모듈 구조 / 서비스 카탈로그

- 모듈: network(VPC) / app-service(Compute) / reverse-proxy(LB) — 클라우드 개념 매핑
- 서비스 목록을 `services.auto.tfvars.json` 으로 분리 → 어드민 콘솔은 JSON 만 수정하면 되는 구조
- `terraform state mv 'module.hello' 'module.service["hello-app"]'` 로 리소스 재생성 없이 주소 이동

### 4. 문서 + Obsidian

- `docs/*.md` + `scripts/build_docs.py` 로 `docs/index.html` 생성 (marked + mermaid)
- Obsidian `클라우드하모니/인프라 구성/` 에 MOC + 문서
- infra 저장소가 public 이라 **공인 IP / MAC 은 저장소 문서에 placeholder**, 실제 값은 Obsidian 에만
  (`~/.claudharmony/private.json` → `scripts/sync_obsidian.py` 가 치환)

### 5. 외부 접속 시도 — 공유기 포트포워딩 (실패)

1. 공인 IP:80 → 공유기 로그인 페이지(`GNT2400`) 응답 → 80 대신 **8888** 사용하기로
2. UPnP 자동 포워딩 시도 → 공유기에 IGD 는 있으나 제어 요청 `Connection refused` (UPnP 비활성)
3. 사용자가 SK브로드밴드 **GW-ME611R** 에 `TCP 8888 → 192.168.45.214:80` 등록
4. 외부(check-host.net 3개국)에서 8888 **타임아웃**, 80 도 타임아웃
5. SK 공유기 WAN 정보 확인 → **WAN IP = 192.168.75.142 (사설)** → **이중 NAT**
6. 상위 공유기 `192.168.75.1` = GNT2400 (공인 IP 보유) — 관리자 계정 없음 → **포트포워딩 불가**

**배운 점**
- 사무실 *안에서* 공인 IP 로 접속해서 보이는 화면은 외부 개방의 증거가 아니다 (공유기 자신이 응답)
- 외부 검증은 반드시 바깥에서 (LTE, check-host.net)
- `traceroute` 2번째 홉이 사설/무응답이면 이중 NAT 를 의심
- 기본 비밀번호 추측으로 남의 장비(상위 공유기)에 들어가지 않는다

### 6. 외부 접속 — Cloudflare Tunnel

- cloudflared 가 **바깥으로** Cloudflare 에 연결 → `https://<랜덤>.trycloudflare.com` 발급. NAT/포트포워딩 무관
- Claude Code 자동 권한 검사가 "외부 공개 터널" 을 2회 차단 → 사용자가 명시적으로 요청한 뒤 실행
- check-host 3개국 200 OK 확인

### 7. dev / prd 환경 분리

- `modules/stack` (환경 1개 전체) + `envs/dev`(8081) / `envs/prd`(80)
- state 를 저장소 밖 `~/.claudharmony/state/<env>.tfstate` 로 (`backend "local" {}` + `-backend-config=path=`)
- `scripts/deploy.sh <env> <service> <image>`: images 파일 갱신 → apply → 헬스 확인 → 배포 기록 커밋 `[skip ci]`
- nginx 에서 `/actuator` 외부 차단, 앱에 `GET /version` 추가

**문제**: workflow 파일 push 거부 `refusing to allow an OAuth App to create or update workflow ... without workflow scope`
**해결**: `gh auth refresh -h github.com -s workflow` (디바이스 코드 인증, 사용자 승인)

### 8. 앱 저장소 분리

- `claudharmony-hello` 로 만들었다가 사용자 요청으로 **`claudharmony-homepage`** 로 이름 변경 (`gh repo rename`) — private, 기본 브랜치 `develop`
- 로컬: `~/workspace/claudharmony-homepage`
- 워크플로: `ci.yml`(PR 빌드), `deploy-dev.yml`(develop push), `deploy-prd.yml`(release/* 수동, 다른 브랜치면 reject)

### 9. Kubernetes 전환

**버전 조사**: kindest/node v1.37.0 (kind v0.33.0 기본), Envoy Gateway v1.9.2, Gateway API v1.6.3.
ingress-nginx 는 2026-03 retire → **Gateway API** 채택.

1. `brew upgrade kind` (0.31 → 0.33), `brew install kubernetes-cli` (1.37.1)
2. Docker 기반 dev/prd destroy (호스트 80 을 kind 가 써야 함), Docker 모듈은 `modules/docker/` 로 보관
3. `platform/cluster` apply — control-plane + worker, `extraPortMappings 30080 → 호스트 80`, 전용 kubeconfig `~/.claudharmony/kubeconfig` (기존 `kind-ch4` 컨텍스트 보호)
4. `platform/gateway` apply — helm `gateway-helm v1.9.2`, EnvoyProxy(NodePort 30080, 서비스 이름 고정 `claudharmony-gateway`), GatewayClass, Gateway(allowedRoutes: 라벨 selector)
5. `modules/k8s/{env,app,tunnel}` + `envs/dev`(hostnames `dev.localhost`) / `envs/prd`(catch-all)
6. 이미지 `kind load` 후 dev/prd apply → Pod Running, HTTPRoute 2개 attached

**문제**: `http://localhost/` 응답 없음. 노드 안에서 `curl 127.0.0.1:30080` 은 200
**원인**: Envoy Service 의 `externalTrafficPolicy: Local`(Envoy Gateway 기본). 호스트 포트는 control-plane 노드로만 들어오는데 Envoy Pod 는 worker 에 있어서 트래픽이 버려짐
**해결**: EnvoyProxy `envoyService.externalTrafficPolicy = "Cluster"`
**결과**: `localhost` → prd, `dev.localhost` → dev, LAN `192.168.45.214` → prd, `/actuator/env` → 302, 터널 2개 모두 200

### 10. 인프라 자동 적용

- `infra-apply.yml`: main push 시 `dorny/paths-filter` 로 바뀐 스택만 — gateway / dev 자동, prd·cluster 수동
- infra 저장소(public)에 "모든 외부 기여자 워크플로 승인 필요" 설정

### 11. Self-hosted runner (대기)

- `scripts/setup-runner.sh` 작성 — 저장소별 러너 등록 + launchd 서비스
- Claude Code 자동 권한 검사가 "상시 실행 서비스 설치" 로 차단 → **사용자가 직접 실행**: `! ~/infra/scripts/setup-runner.sh`

### 12. 문서 개편 & 정리

- docs 전면 개편: 01 아키텍처(K8s), 03 운영(Runbook), **05 K8s 학습 가이드**, 06 CI/CD, 07 작업 기록
- `sync_obsidian.py`: 제목의 `/` 를 `·` 로 치환 (`06 CI/CD.md` 가 하위 폴더로 해석돼 실패하던 문제)
- 러너가 없어 대기 중이던 **옛 코드(Docker 기준) Infra apply 실행 2건 취소** — 러너가 붙는 순간 K8s state 에 옛 코드가 적용되는 것을 방지
- 앱 `Deploy dev` 대기 1건은 유지 → 러너 등록 시 E2E 테스트로 사용

### 13. 홈페이지 개발은 다른 세션이 담당

- 사용자: "홈페이지는 다른 세션이 만들고 있어" → `~/workspace/claudharmony-homepage` 는 이 세션에서 더 수정하지 않음
- 다른 세션(ai-root-78)에 **앱 ↔ 인프라 계약**(Dockerfile, 8080, actuator probe, 512Mi, 이름 고정, `/version`, 워크플로 유지) 전달
- 계약은 [CI/CD](06-cicd.md) 문서에 표로 정리
- 주의: 러너가 등록되면 develop push 가 즉시 dev 배포를 트리거한다

### 14. 러너 등록 & dev 파이프라인 첫 실행

- 사용자가 `scripts/setup-runner.sh` 실행 → 러너 2개 online (launchd 서비스)
- 대기 중이던 `Deploy dev` 가 바로 실행 → **14초 만에 ✓ 성공 표시인데 실제로는 배포 안 됨** (`/version` 이 그대로 `dev-initial`)

**문제 1**: `deploy.sh: Permission denied`
**원인**: `Write` 로 만든 파일이라 git 에 실행 권한(100755)이 없었음 (`git ls-files -s` 로 확인)
**해결**: `chmod +x` + `git update-index --chmod=+x`

**문제 2**: 실패했는데 워크플로가 성공으로 표시
**원인**: `run:` 의 기본 셸은 `bash -e {0}` — `deploy.sh | tee deploy.log` 에서 파이프 앞쪽 실패를 무시
**해결**: 워크플로에 `defaults.run.shell: bash` → GitHub 이 `bash --noprofile --norc -eo pipefail` 로 실행
**배운 점**: CI 에서 `| tee` 를 쓸 땐 반드시 pipefail. "성공" 표시만 믿지 말고 결과(`/version`)로 검증

**문제 3**: 배포용 infra 클론이 오래된 스크립트를 실행할 수 있음 (클론이 있으면 pull 안 함)
**해결**: 워크플로에서 deploy 전에 `git -C $INFRA pull --ff-only`

→ 홈페이지 저장소 워크플로 2개만 GitHub API 로 커밋 (다른 세션의 로컬 작업은 건드리지 않음, 해당 세션에 알림)

- 재실행 결과: **dev = `dev-c0184f6` 롤링 업데이트 성공** ✅

**문제 4**: 배포 기록 push 실패 `could not read Username for 'https://github.com': Device not configured`
**원인**: launchd 서비스로 도는 러너는 `gh` 의 키체인 인증을 못 읽음
**임시 조치**: 기록 커밋을 수동 push (`f54bd26`)
**해결 (진행 중)**: infra 저장소 전용 **SSH deploy key** — `scripts/setup-deploy-key.sh` (Claude Code 권한 검사가 "접근 권한 추가" 로 차단 → 사용자 실행 필요)
**추가**: `deploy.sh` 가 기록 push 실패 시 **에러로 종료**하도록 변경 (기록 누락 시 다음 apply 가 옛 이미지로 되돌릴 위험)

### 15. Deploy key 설정 (사용자 실행)

- 사용자가 `scripts/setup-deploy-key.sh` 실행 → deploy key 등록(id 167503523) 성공, 연결 테스트 실패

**문제**: `ssh: connect to host github.com port 22: Operation timed out`
**원인**: 사무실 네트워크가 **아웃바운드 22번 포트 차단**
**해결**: GitHub 의 SSH-over-443 사용 — 원격을 `ssh://git@ssh.github.com:443/ParkSeWoo/claudharmony-infra.git` 로 (스크립트 수정 `e269b3d`)
**확인**: `env -u SSH_AUTH_SOCK git ls-remote` 성공 — 에이전트/키체인 없이 deploy key 만으로 접근됨
**배운 점**: 회사/사무실망은 22 를 막는 경우가 많다 → `ssh -T -p 443 git@ssh.github.com`

- 다른 세션으로 보낸 공지 2건은 권한 모드 차이로 **보류 후 만료(미전달)** → 사용자 요청으로 재전송 (승인 대기)
- prd 배포 테스트(`release/20261024` 생성 + Deploy prd 실행)는 Claude Code 권한 검사가 "운영 배포" 로 차단 → 전략대로 **사용자가 수동 실행**

### 16. prd 배포 E2E 테스트 (사용자 요청으로 실행)

1. `release/20261024` 브랜치 생성 (develop `c0184f6` 기준 — 홈페이지 작업 반영 전, 파이프라인 검증용)
2. `gh workflow run deploy-prd.yml --ref release/20261024` → **success** (deploy ✓, reject skipped)
3. 검증
   - `http://localhost/version` → `{"version":"20261024-c0184f6","env":"prd"}`
   - prd 터널 주소 → 같은 응답 (외부 접속 OK)
   - infra 저장소에 `5944985 claudharmony-deploy: deploy(prd): hello-app=...:20261024-c0184f6 [skip ci]` — **deploy key 로 자동 커밋 성공**
   - `[skip ci]` 라 Infra apply 워크플로는 실행되지 않음 ✓
4. 가드 테스트: `develop` 에서 Deploy prd 실행 → **reject 잡 실패, deploy skipped**, prd 버전 그대로 ✓

**남은 절차 (사용자)**: prd 확인 후 `release/20261024` → `main` PR merge, `main` → `develop` back-merge.
(홈페이지 실제 릴리스는 다른 세션 작업이 develop 에 들어온 뒤 새 release 브랜치로)

---

## 템플릿 (다음 작업용)

```markdown
### N. 작업 제목

- 무엇을 했나
- 결과 (명령/출력 요약)

**문제**: 증상
**원인**: 왜
**해결**: 어떻게
**배운 점**: 다음에 기억할 것
```
