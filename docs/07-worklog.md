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
| 14 | web / api 분리 — 카탈로그·동시배포 잠금 | ✅ |
| 15 | api / web 러너 등록 | ✅ (사용자 실행, 러너 4개 online) |
| 16 | dev 에 api → web 배포, hello-app 제거 | ✅ dev `/` = web `dev-05aa8f3` |
| 17 | prd 에 api → web 배포, hello-app 제거 | ✅ prd `/` = web `20261024-05aa8f3` |
| 18 | 도메인 claudharmony.io 연결 (Named Tunnel) | ✅ apex/www → prd, dev. → dev |
| 19 | k9s / KUBECONFIG 정리 | ✅ |

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

### 17. homepage 사이클 마무리 (사용자 요청)

- PR #1 `release/20261024` → `main` merge (`c1b09bb`), `main` → `develop` back-merge (`45d45c0`, GitHub merges API)

### 18. 홈페이지 → web / api 분리 (다른 세션 ai-root-78 요청)

다른 세션이 홈페이지를 두 저장소로 분리하고 카탈로그 추가를 요청:
- `claudharmony-web` — SvelteKit 3 (Node 24), :3000, `/`, probe 경로는 actuator 와 동일하게 맞춤, `/version` 제공
- `claudharmony-api` — Spring Boot 4.1.2 / Java 25, :8080, 내부 전용
- 두 저장소 워크플로에 #14 의 수정(pipefail, infra pull) 반영 확인 (`gh api .../contents`)

작업:
1. `envs/dev`, `envs/prd` 카탈로그에 `api`(내부), `web`(`/`, 256Mi) 추가 — 이미지가 없어 리소스는 아직 생성 안 됨 (`local.deployed` 필터)
2. **동시 배포 대비**: 서비스가 여럿이면 러너들이 같은 infra 클론/state 를 동시에 씀
   - `deploy.sh`: `mkdir` 기반 잠금 (`~/.claudharmony/deploy.lock`, 최대 10분 대기). macOS 에 `flock` 없음
   - 첫 버전에 잠금 실패 시 남의 잠금을 지우는 버그 → 재작성, 가짜 스크립트 2개 동시 실행으로 **순차 처리 확인**
   - `infra.sh`: `terraform plan/apply -lock-timeout=10m`
3. push → **Infra apply 워크플로 첫 실전 실행**: changes 감지 → dev 만 실행 → `No changes` ✓
4. 러너 등록(api, web)은 사용자 실행 필요: `scripts/setup-runner.sh claudharmony-api claudharmony-web`

**배운 점**: Gateway API 에서 같은 경로의 HTTPRoute 가 겹치면 **생성 시각이 오래된 라우트가 우선** → 새 서비스를 먼저 띄우고 옛 라우트를 지우는 방식으로 무중단 전환 가능

### 19. api / web 러너 등록

- 사용자가 `scripts/setup-runner.sh claudharmony-api claudharmony-web` 실행 → 2개 online
- 등록 직후 infra 러너가 **offline** 으로 표시

**원인**: 직전 Infra apply 잡을 끝낸 뒤 GitHub 브로커 연결이 끊김 (`SocketException (89): Operation canceled`) — 러너가 자동 재시도(backoff)
**조치**: 재부팅 아님(uptime 41일), launchd 프로세스 살아 있음 확인 → 1분 내 **online 복귀**
**배운 점**: 러너 상태는 `gh api repos/<r>/actions/runners`, 원인은 `~/.claudharmony/runners/<repo>/_diag/Runner_*.log`

- 다른 세션(ai-root-78)에 준비 완료 알림 → 다음: develop push 로 dev 에 api → web 배포

### 20. dev: hello-app → web 전환

다른 세션(ai-root-78)이 develop push → **Deploy dev 자동 배포**: api `dev-09e3172`, web `dev-05aa8f3` (배포 잠금으로 순차 처리, 기록 자동 커밋)
- ai-root-78 검증: port-forward 로 web `/`, `/blog`, `/blog/gateway-api` 200, `/blog/nope` 404, web → `http://api` 연동(글 7개)
- 이 시점 `dev.localhost` 는 **먼저 생긴 hello-app 라우트**가 응답 (`dev-45d45c0`) — 예상대로

전환:
1. `envs/dev/services.auto.tfvars.json`, `images.auto.tfvars.json` 에서 `hello-app` 제거
2. `plan`: hello-app 의 HTTPRoute / Deployment / Service **3 destroy**, 나머지 변경 없음
3. push(`6a558b1`) → **Infra apply 가 dev 자동 적용** ✓
4. 검증: `http://dev.localhost/version` → `dev-05aa8f3`, `<title>클라우드 하모니`, dev 터널도 web, prd 는 `20261024-c0184f6` 그대로

**배운 점**: 같은 경로 라우트가 겹칠 때 옛 라우트를 지우는 순간 새 라우트로 넘어감 → 사전 검증(port-forward) + 라우트 삭제 = 무중단 전환

**협업 이슈**: 이 세션 → ai-root-78 메시지가 계속 보류/만료됨. 원인은 두 세션의 **권한 모드 차이**(ai-root-78 = bypass, 이 세션 = auto). 반대 방향(ai-root-78 → 이 세션)은 전달됨.

### 21. prd: api → web 배포, hello-app 제거 (사용자 요청 "prd 에도 web 배포해줘")

1. claudharmony-api, claudharmony-web 에 `release/20261024` 생성 (각 develop = dev 검증 커밋 `09e3172`, `05aa8f3`)
2. **api 먼저** Deploy prd → success, `api 1/1 20261024-09e3172`
3. web Deploy prd → success, `web 1/1 20261024-05aa8f3`
4. 전환 전 내부 검증: `kubectl -n prd port-forward svc/web 3300:80` → `/`, `/blog`, `/version` 200 (`/blog` 로 web → api 연동 확인)
5. `envs/prd` 카탈로그·images 에서 hello-app 제거 → plan `3 to destroy` → push → **Infra apply 수동 실행(stack=prd)** success
6. 검증
   - `http://localhost/version` → `{"env":"prd","version":"20261024-05aa8f3"}`, LAN `192.168.45.214` → `<title>클라우드 하모니`
   - 외부(check-host 9개 노드: DE/PT/US/IN/RO/HK/IL/NL): prd 터널 `/`, `/blog`, `/version` 모두 200
   - prd 리소스: Deployment `api`, `tunnel`, `web` / HTTPRoute `web`

**남은 것**: 각 저장소 `release/20261024` → `main` merge, `main` → `develop` back-merge / claudharmony-homepage archive

### 22. 터널 순간 끊김 조사

- 사용자: "갑자기 안 나온다" → 로컬/외부 모두 200, 에셋·SSR 정상
- `kubectl logs deploy/tunnel` 에서 15:44 KST prd·dev 터널 **동시에** `QUIC ... timeout: no recent network activity` → 1초 내 재연결
- 같은 시각 러너도 브로커 연결 끊김 → **사무실 회선 순간 단절**로 판단
- 대책: 고정 도메인 + named tunnel 커넥터 이중화 (#23)

### 23. 도메인 claudharmony.io 연결

1. 도메인: **Cloudflare Registrar** 에서 `claudharmony.io` 구매 (네임서버 자동, WHOIS 비공개)
2. `platform/edge` 스택 작성 — cloudflare provider `~> 5.27.0` (5.28.1 은 4일 된 버전이라 제외), `terraform providers schema -json` 으로 v5 리소스 속성 확인 후 작성
3. `infra.sh`: `edge` 스택 추가, 이 스택만 `~/.claudharmony/cloudflare.env` 로드
4. 토큰 발급 (계정 API 토큰) — 사용자와 화면 보며 진행

**문제 1**: 터널 생성 `10000 Authentication error`, 그러나 터널 목록/zone/DNS 조회는 성공
- 빈 body POST 로 판별 → 여전히 10000 = 권한 문제
- 추가 단서: `access/apps` → `access.api.error.not_enabled` → **Zero Trust 미개설**
- 사용자가 Zero Trust(Free) 활성화 → Access 는 정상화, 터널 생성은 여전히 10000

**문제 2**: 토큰에 터널 쓰기 권한 없음
- UI 에서 "Cloudflare Tunnel" 검색 시 **Argo Tunnel (Legacy)** 만 보임 → 이것만으론 부족
- 정책 카운터가 `0/72` → 앞서 체크한 권한이 저장되지 않았던 것도 확인
- **Cloudflare One Connector: cloudflared — Edit** (+ Connectors, Access, Argo Legacy) 추가·저장 → 빈 body POST 가 `1030 missing field name` = 권한 통과

5. `edge apply` → 터널, ingress 설정, DNS 3, Secret, cloudflared × 2 생성
   - 커넥터 로그: `Registered tunnel connection` ×4 (icn01/05/06 — 서울 엣지)
6. `envs/dev` HTTPRoute hostnames 에 `dev.claudharmony.io` 추가
7. 검증: `https://claudharmony.io`·`www` → prd `20261024-05aa8f3`, `dev.` → dev, 인증서 Let's Encrypt (Cloudflare 자동), 외부(BG/IN) 200
8. **임시 quick tunnel 제거** (`enable_tunnel = false`) — dev 는 main 머지로 자동, prd 는 수동 apply
9. `infra.sh url/check` → 도메인 기준으로

**배운 점**
- Cloudflare 권한 이름은 자주 바뀐다 → API 오류 문서 링크(`documentation_url`)와 실제 호출로 판별
- 인증 vs 입력 오류를 빈 body POST 로 구분
- 터널 하나에 모든 호스트 → Gateway 로, 환경 구분은 HTTPRoute 에서: 라우팅 규칙이 한 곳(K8s)에 모임

### 24. k9s 에서 클러스터가 안 보이던 문제

**원인**: `~/.zshrc` 의 `KUBECONFIG` 가 lima k3s 파일 하나만 가리킴 (컨텍스트 0개). 우리 클러스터는 전용 `~/.claudharmony/kubeconfig`
**해결**: `KUBECONFIG` 를 3개 파일 합치기 + `k9ch`/`kch` alias (백업 `~/.zshrc.bak-20261024`) → `kubectl config get-contexts` 에 `kind-claudharmony`, `kind-ch4` 표시

### 25. 기술 블로그 글 추가 — 도메인 연결

- 블로그 글 저장 위치: `claudharmony-api` 의 `src/main/resources/posts/*.md` (파일명 = slug, YAML front matter: title/summary/date/tags)
- 글 `custom-domain-cloudflare-tunnel.md` 작성 — 순서, 최소 권한 토큰 표, Terraform 스니펫, 막혔던 곳(권한 이름·빈 body 판별·0/72·영역 범위)
- **민감 정보 제외**: 토큰·Account ID·Tunnel ID·이메일·공인 IP 없음 (정규식 검사)
- 다른 세션 저장소라 **새 파일 하나만** API 로 develop 에 추가(`46aeb0b`) → Deploy dev 성공 → https://dev.claudharmony.io/blog/custom-domain-cloudflare-tunnel 200
- prd 반영은 api release 브랜치로 (사용자 확인 후)

### 26. k9s 기본 설정에도 클러스터 등록

- 사용자: k9s 에 여전히 안 보임 → 새 zsh 에선 정상(`kind-claudharmony`), **수정 전에 열린 터미널**이 원인
- 셸 환경과 무관하게 보이도록 `~/.kube/config` 에 `kind-claudharmony` 병합 + 기본 컨텍스트 지정 (백업 `~/.kube/config.bak-20261024`)
- 주의: 클러스터 재생성 시 다시 병합 필요 (03 운영 가이드)

### 27. k9s "아무것도 안 보임" 해결 + metrics-server

**증상**: k9s 컨텍스트 0개 → (설정 재로드 후) 연결은 됐는데 화면이 빈 것처럼 보임
**원인 (k9s 로그 `~/Library/Application Support/k9s/k9s.log`)**
1. 17:18 `invalid context specified: ""` — 예전 터미널 환경
2. 17:19~ `No resources found for v1/pods in "default"` — **연결은 됐고 비어 있는 `default` 네임스페이스를 보고 있었음**
**해결**
- k9s 컨텍스트 설정(`clusters/kind-claudharmony/kind-claudharmony/config.yaml`): 기본 네임스페이스 `all`, 즐겨찾기 `all, prd, dev, edge, envoy-gateway-system` (숫자키 0~4)
- `platform/addons` 스택 신설 → **metrics-server** (Helm 3.14.0, kind 용 `--kubelet-insecure-tls`) → `kubectl top nodes` / k9s CPU·MEM 표시
- `infra.sh addons`, Infra apply 수동 옵션에 `addons` 추가

**배운 점**: k9s 가 "안 보이면" 먼저 로그 — 연결 실패와 빈 네임스페이스를 구분

### 28. DB 선택 — PostgreSQL

- 사용자 방향: **도메인은 앱에, DB 는 단순 저장·조회**. 향후 위치 기반·Redis·트렌드 크롤링·블로그 수집 알림·AI(전용 벡터 DB)·**대량 데이터**
- 결론: 서비스 DB = **PostgreSQL + PostGIS**, 벡터 = **Qdrant(전용)**, 대량 트렌드 = **ClickHouse**, 원본 = 오브젝트 스토리지, 캐시 = Redis, 버퍼 = Redpanda → [데이터베이스 로드맵](09-database.md)
- PG 를 고른 이유: K8s Operator(CloudNativePG) 성숙도 → 백업/복구 선언형, PostGIS, JSONB/부분 인덱스/전문검색(조회 도구), 이식성(RDS/Cloud SQL), 라이선스

### 29. PostgreSQL 구축 (dev, prd)

1. 버전 조사: CNPG **1.30.1**(chart 0.29.1, 2026-09-23), 이미지 `postgis:18.6-3.6.4-standard-trixie` (ghcr 태그 목록 페이지네이션으로 PG18 확인)
2. `platform/database`: CNPG Operator (Helm) → CRD 11개 (`clusters`, `databaseroles`, `scheduledbackups` …)
3. `kubectl explain cluster.spec.managed.roles / bootstrap.initdb` 로 1.30 스펙 확인 후 `modules/k8s/postgres` 작성
   - initdb: DB `claudharmony`, owner `app`, `CREATE EXTENSION postgis`
   - managed role `readonly` (`pg_read_all_data`, 연결 5) + Terraform 랜덤 비밀번호 Secret
   - 첫 초안의 `GRANT ... TO readonly` 를 initdb SQL 에서 제거 — **initdb 시점엔 managed role 이 아직 없어 실패할 수 있음** → `inRoles` 로 대체
   - `kubectl_manifest` `wait_for status.phase = "Cluster in healthy state"`
4. `modules/k8s/app`: `secret_env` (Secret → 환경변수) 추가 / `modules/k8s/env`: `database` 변수, 카탈로그 `"database": true` → `SPRING_DATASOURCE_*` 주입
5. 적용 전 확인: api `build.gradle` 에 JDBC/JPA 없음 → 환경변수 주입해도 무시됨(안전)
6. dev apply → `Cluster in healthy state` (48초), 검증
   - `PostgreSQL 18.6`, `postgis 3.6.4`, `shared_buffers 96MB`, `Asia/Seoul`
   - `readonly`: `postgis_version()` 조회 OK, `CREATE TABLE` → `permission denied` ✓
   - api Pod 에 `SPRING_DATASOURCE_URL/USERNAME/PASSWORD` 주입, 정상 Running
7. prd apply → healthy, 사이트 정상
8. `scripts/db.sh`: port-forward + 접속 정보 출력 + **비밀번호 클립보드 복사** (화면 미출력). 로컬에 psql 이 없어 `postgres:18-alpine` 일회용 컨테이너로 검증 ✓

**남은 것**: 백업(Barman Cloud → R2), api 에 JPA/Flyway (다른 세션), Docker 메모리 증설

### 30. 관리자 콘솔 1단계 (조회) — claudharmony-console

목표: "AWS/GCP 처럼 관리자 페이지에서 시작·종료·확인" → **조회부터**, 별도 저장소
1. 설계: 조회 = K8s API 읽기 / 변경(2단계) = 카탈로그 Git 커밋 → Terraform (단일 진실 원천 유지)
2. 인프라: `envs/console` (환경 모듈 재사용) + ServiceAccount + **ClusterRole 읽기 전용(Secret 제외)**, app 모듈 `service_account`
3. 앱: Spring Boot 4.1.2 / Java 25 (api 와 동일), fabric8 7.9.0 (8.0.0 은 1개월 된 메이저 → 7.x 최신), Thymeleaf + htmx 2.0.11
   - 화면: 대시보드(노드·구성요소·외부 접속·환경 카드·배포 이력), 환경 상세(Pod·DB·라우트·경고), 로그
   - 배포 이력: infra(public) 커밋 메시지 `deploy(env): svc=img:tag` 파싱
   - `/env/nope` → 404 (설정된 환경만 조회)
4. 로컬 실행(`KUBECONFIG`)으로 전 페이지 200 확인 → 이미지 빌드 → `deploy.sh console console …` → `http://console.localhost` 정상, RBAC 오류 없음
5. 저장소 `claudharmony-console` (private, main) 생성·push

**문제 1 — 공개 주소가 보호 없이 열림 (1분여)**
- edge 에 `console.claudharmony.io` + Access 를 한 번에 apply → DNS·터널 설정은 성공, **Access 는 `auth.forbidden`** (토큰에 Access 쓰기 없음)
- 그 순간 콘솔 호스트가 prd catch-all 로 공개 홈페이지를 보여줌 → **즉시 hostname 제거 apply** (530 확인)
- 재발 방지: Access 성공 후 DNS 생성되도록 `depends_on`, 토큰 권한 추가 후 재적용
- **배운 점**: 보호 장치가 필요한 공개는 "보호 먼저, 노출 나중" 순서를 코드로 강제

**문제 2 — Google Java Style 적용 (사용자 요청)**
- Spotless 8.9.0 + google-java-format 1.37.0 → 모든 파일 `InvocationTargetException`
- `--add-exports` jvmargs 추가해도 동일, gjf jar 직접 실행은 정상 → **Spotless 보다 나중에 나온 gjf 1.37 과의 비호환**
- gjf **1.36.1** 로 내려서 해결 (`gradle.properties` 의 add-exports 는 유지)
- CI: PR 에 `spotlessCheck build`, 배포 워크플로도 `spotlessCheck` 선행

**남은 것**: 토큰 Access 권한 → Access + 공개 주소 / console 저장소 러너 등록 / 2단계(제어)

### 31. 콘솔 자동 새로고침 → 수동 버튼

- 사용자: "10초마다 자동 새로고침은 나중에" → htmx `every 10s/60s/5s` 제거, `refresh from:body` 이벤트 + 상단 **새로고침** 버튼(마지막 갱신 시각 표시)
- 배포 `console-7967449` (러너 미등록이라 `deploy.sh` 수동 실행)

### 32. api 가 PostgreSQL 사용 시작 (api 세션 알림)

- api 세션(ai-root-78): 기존 CNPG(`pg-rw`, `database=true` 주입) 그대로 사용, 추가 인프라 요청 취소
- 확인: dev `flyway_schema_history` → `1 trend success`, `trend_snapshot` 1행 / `trend_keyword` 10행, https://dev.claudharmony.io/trends 200 (web `dev-4aa262a`)
- 계약 표(06)·DB 문서(09)에 "api 는 database=true, 스키마는 Flyway" 반영
- 참고: 트렌드 데이터가 커지면 [로드맵](09-database.md)대로 ClickHouse 로 분리

### 33. 스키마 관리 Flyway → Atlas (선언형)

배경: 사용자 "개발은 자동, 운영은 앱이 스키마 바꾸면 위험" → 대안 비교(Liquibase/Atlas/Bytebase/pgroll) → **Atlas** 선택 (Terraform 과 같은 plan/apply 감각)
- 확인 중 발견: api 세션이 이미 prd 에 트렌드 기능 배포 → **Flyway 가 prd 기동 시 자동으로 테이블 생성** (09:18). 안전한 변경이었지만 우려한 경로가 실제로 쓰임
1. Atlas `1.3.3-community` (1.3.4/1.3.5 는 2주 미만), `schema inspect` 로 dev 현재 구조 → `db/schema.sql`
2. **문제**: 공식 `postgis/postgis:18-3.6` 은 arm64 이미지 없음 → `imresamu/postgis:18-3.6.1-trixie` (PostGIS 도커 관리자 멀티아치 빌드) 로 차이 계산용 DB
3. `scripts/db-schema.sh <env> plan|apply|check` — prd: 위험 변경 차단, `CONFIRM="apply prd"`, pg_dump 백업. 제외: `spatial_ref_sys`, `flyway_schema_history`
4. 테스트(dev plan): 현재 그대로 → `Schema is synced` / 컬럼 추가 → `ADD COLUMN` / 컬럼 삭제 → ⚠️ 위험 감지 / `check` 대기 변경 시 exit 3. prd 는 **계획만**(읽기) — prd apply 거부 테스트는 Claude Code 권한 검사가 "운영 배포" 로 차단 (올바른 차단)
5. api 저장소 (다른 세션 로컬은 안 건드리고 GitHub 에 **커밋 1개** `d89b26a`): `db/schema.sql`, `deploy-dev`(스키마 자동 적용 → 앱), `deploy-prd`(check), `db-schema-prd`(수동·확인문구·백업)
6. dev 배포에서 새 단계 실행 확인: `DB schema (dev 자동 적용): success` → `Schema is synced`

남은 것: api 코드에서 Flyway 제거 + `ddl-auto=validate` (api 세션) → 이후 `flyway_schema_history` 정리

### 34. Flyway 제거 (api 세션) + dev 정리

- api 세션: Flyway 의존성·`V1__trend.sql` 삭제, JPA 가 아니라 `JdbcClient` 라 `ddl-auto` 대신 **기동 시 information_schema 검증**(없으면 기동 실패), Testcontainers 도 `db/schema.sql` 사용, 테스트 35개 통과 → dev `dev-93204f6`
- 인프라: dev `flyway_schema_history` DROP → 남은 테이블 `trend_snapshot, trend_keyword, spatial_ref_sys`, Atlas `check` = 변경 없음
- prd 는 아직 Flyway 포함 버전(`20261024-63e8dca`) → release → DB schema prd → Deploy prd 이후 prd 이력 테이블 정리 예정

### 35. 구성도·가이드 문서 정리 (학습 기준)

- `01-architecture` 전면 개편: 실제 클러스터 조사(ns·deploy·svc·route·pg·pvc·helm·state·저장소) 기반 — 시스템 컨텍스트, 물리/노드, Namespace 논리도, 요청 시퀀스, 배포 흐름, Terraform 스택 의존, 데이터, 보안 경계, 버전, 설계 결정
- `11-learning-guide` 신규: 10단계 커리큘럼(개념 → 우리 구성 → 확인 명령 → 실습 → 체크리스트) + 장애 사례 복기 표 + 다음 과제
- 실습은 dev·읽기 전용만 (prd 변경 명령 없음)

### 36. 정리 (사용자 요청 "불필요한 거 정리")

| 대상 | 처리 | 되돌리기 |
|------|------|----------|
| Docker 이미지 `claudharmony/*` 31개 | **21개 삭제** — hello/hello-app 전부, 오래된 dev/prd 태그, console-initial. 남김: 배포 중 5개 + prd 롤백용 이전 버전(api `63e8dca`, web `05aa8f3`) + `:local`(api 세션 로컬용) | 다시 빌드 |
| kind 노드 안 미사용 이미지 | `crictl rmi --prune` (worker 38→34) | 롤백 시 deploy.sh 가 kind load |
| 빌드 캐시 | 24시간 지난 것만 prune (다른 프로젝트 캐시 보호) | — |
| 구 `claudharmony-homepage` | 러너 서비스 중지·등록 해제·디렉토리 삭제, 저장소 **archive**, 로컬 클론 삭제(변경·미push 없음 확인) | GitHub 에서 unarchive |
| `modules/docker/` (K8s 이전 Docker 모듈) | 삭제 | Git 이력 |
| `setup-runner.sh` 기본 대상 | homepage → web, api, console | — |
| prd `flyway_schema_history` | ✅ 사용자 직접 DROP (#39) — Claude Code 권한 검사가 운영 DB 쓰기를 차단해서 | pg_dump 백업 |

**문제**: 이미지 일괄 삭제가 조용히 실패 — `docker rmi $RM` 에서 **zsh 는 따옴표 없는 변수를 단어로 쪼개지 않음** → 줄바꿈 포함 한 덩어리로 전달. `while read` 로 하나씩 처리해서 해결
**남겨 둔 것**: 다른 프로젝트 이미지·볼륨(airflow, qdrant, kind ch4), Atlas 임시 DB 컨테이너(재사용), Terraform state `.backup`

### 37. 로컬에서 PostgreSQL 확인 환경

1. `brew install libpq` → psql 18.6 (`~/.zshrc` PATH 추가). 이 Mac 의 DB 도구는 IntelliJ 뿐
2. `scripts/db.sh` 개편: `up/down/status/info/psql/pgpass` — 비밀번호는 기본 가림, `~/.pgpass` 는 **prd 쓰기 계정 제외**
3. **문제**: 백그라운드 `kubectl port-forward` + 재연결 루프 → 첫 접속 뒤 계속 `Connection refused`
   - 처음엔 상태 확인용 `nc -z` 탓으로 보고 `lsof` 로 바꿨으나 동일
   - 포그라운드 실행으로 원인 확인: `error forwarding port 5432 ... read: connection reset by peer` → `error: lost connection to pod` — **클라이언트가 끊을 때 DB 쪽 리셋에 port-forward 프로세스가 종료** (kubectl 의 알려진 한계)
   - **해결**: port-forward 를 버리고 `modules/k8s/postgres` 에 NodePort `pg-local`(dev 31432 / prd 32432) + Mac 의 **socat 프록시 컨테이너**(127.0.0.1 전용, unless-stopped) → 12회 연속 접속 성공, 재시작 0
4. 적용 중 주의: 로컬 infra 가 원격보다 뒤처진 상태의 plan 이 **api·web 을 옛 이미지로 되돌리려 함** → 적용 전 발견, `git pull` 후 재plan = Service 1개 추가만. **apply 전에 항상 최신 pull**
5. readonly 로 INSERT → `permission denied` 확인, IntelliJ 연결 방법·prd 읽기전용 설정 문서화

### 38. DataGrip 으로 DB 연결

- 사용자 보유 도구: JetBrains **DataGrip** → `127.0.0.1:15432`(dev) / `25432`(prd), `readonly` 로 연결 성공
- 권장: prd 데이터 소스 Read-only + 빨간색 표시

### 39. prd Flyway 이력 테이블 삭제 → Atlas 제외 목록 정리

- 사용자가 직접 실행: `kubectl -n prd exec pg-1 -c postgres -- psql -U postgres -d claudharmony -c "DROP TABLE IF EXISTS flyway_schema_history;"` → `DROP TABLE`
- dev 는 #37 에서 이미 삭제 → 이제 dev·prd 모두 public 테이블 = `trend_snapshot, trend_keyword, spatial_ref_sys`
- `scripts/db-schema.sh` 제외 목록: `spatial_ref_sys, flyway_schema_history, flyway_schema_history.*` → **`spatial_ref_sys` 만**
- 확인: `db-schema.sh dev check` / `prd check` → 둘 다 `Schema is synced` ✅

**배운 점**: 운영 DB 에 쓰는 일회성 명령은 사람이 `!` 로 직접 실행 — 자동화 도구가 운영 데이터를 바꾸지 않게 하는 안전장치가 제대로 동작한 것

### 40. 인증 서버 Keycloak 추가

사용자 요청: "키클락 추가 — 다양한 로그인 인증 서비스 관리, 내 시스템과 연동" + 블로그(스크린샷). 앱 연동은 앱 세션 담당 → 인프라만.

1. 버전: Keycloak `26.7.5`(2026-09-30, 2주 이상 지난 최신), Terraform provider `keycloak/keycloak ~> 5.10.0`
2. `platform/identity` — Namespace `identity`, 전용 CNPG `pg`(DB `keycloak`, 2Gi, 256Mi), bootstrap **client**(사람 계정 대신 client_credentials), Deployment(`start`, Recreate, 관리 포트 9000 probe), Service, HTTPRoute 2개
   - 공개 `auth.claudharmony.io`: `/realms/claudharmony`, `/realms/claudharmony-dev`, `/resources`만 → 나머지는 https://claudharmony.io/ 로 302
   - 관리 `auth.localhost`: 전체 (터널이 받지 않는 호스트 = 사무실 Mac 전용)
3. `platform/realms` — realm `claudharmony`(prd)/`claudharmony-dev`(dev), 역할 `user`(기본)/`admin`, client `web`(confidential+PKCE, redirect URI 제한, aud=api 매퍼)/`api`(bearer-only)/`console`(prd), master 관리자 `claudharmony-admin`, dev `tester`, 앱 Namespace에 Secret `keycloak-web|api|console|tester` — 27개 리소스
4. 소셜 로그인 `social.tf` (Google·GitHub·카카오) — `~/.claudharmony/identity.env` 값이 있을 때만 생성. 가짜 값으로 **plan만** 검증(6개 생성 예정 확인)
5. `infra.sh`: 스택 `identity`, `realms` 추가, realms는 실행 중에만 port-forward(18080) + bootstrap 비밀 주입. CI 수동 실행 목록에도 추가
6. `platform/edge` hostnames에 `auth.claudharmony.io` 추가 — plan: DNS 1 추가, 터널 설정 1 변경. **apply는 자동 권한 검사가 거부(공개 DNS 변경)** → 사용자 실행 대기
7. 확인 (Gateway에 Host 헤더로): 공개 realm 200, `/admin`·`/realms/master`·`/` 302 → https://claudharmony.io/, issuer `https://auth.claudharmony.io/realms/claudharmony`
8. 관리 콘솔 스크린샷 9장 (Playwright + 로컬 Chrome for Testing) → `docs/images/keycloak/`, 문서 [12. 인증 서버](12-identity.md), Obsidian 동기화에 이미지 복사 추가
9. 메모리 사용: Keycloak 약 560Mi, DB 73Mi

**문제 1**: Keycloak 재시작 2회 — `Connection to pg-rw.identity.svc:5432 refused`
**원인**: DB 출력값(jdbc_url)은 계산만으로 알 수 있어 Terraform이 Deployment를 DB와 동시에 만듦
**해결**: `depends_on = [module.db]`

**문제 2**: 관리 콘솔 빈 화면 — `https://auth.claudharmony.io/realms/master/.../3p-cookies` 요청 실패
**원인**: `KC_HOSTNAME_ADMIN`은 콘솔 화면 주소만 바꿈. master realm 로그인은 여전히 공개 주소로 가는데, 그 경로는 일부러 막아 둠
**해결**: master realm **Frontend URL**만 `http://auth.localhost`로 (`terraform_data` + REST PUT, master realm 전체를 Terraform으로 가져오면 기본값으로 덮어쓸 위험)

**문제 3**: 공개 주소 리다이렉트가 `http://claudharmony.io/` → `RequestRedirect`에 `scheme = "https"` 명시 (터널 안쪽 요청은 http)

**문제 4**: `*.localhost`는 브라우저만 127.0.0.1로 풀어 줌(macOS 시스템 DNS·Terraform은 못 풂) → realms 스택은 port-forward

**배운 점**: 인증 서버는 "공개할 경로"를 먼저 정한다. 토큰 issuer는 하나(공개 주소)로 고정하고, 서버끼리 통신만 클러스터 안 주소로.

---
### 41. 장애: Docker VM 메모리 고갈 → prd·dev 502/530 (약 15분)

- 증상: edge apply 직후 공개 로그인 화면 확인 중 `auth`·prd·dev 모두 502/530, `kubectl` TLS handshake timeout, Docker VM CPU 900%
- 노드 안에서 확인: 메모리 7.8GB 중 남은 것 93MB, **swap 1GB 전부 사용**, load average 550, `/proc/pressure/memory` full 52~59% → 거의 모든 Pod가 두 번 연속 재시작
- 원인: Docker Desktop VM(7.65GB) 하나에 여러 프로젝트가 함께 떠 있음
  - claudharmony kind 클러스터 (+ 이번에 추가한 Keycloak ~600Mi, DB ~70Mi)
  - 다른 kind 클러스터 `ch4` (노드 3개, ~1.2GB)
  - Airflow·Qdrant `digest_*` 컨테이너 (~1.5GB)
  - 장애 직전에 뜬 로컬 컨테이너 `dev-keycloak-1` (~600Mi, 이후 사라짐)
- 조치: 클러스터 안 Keycloak `replicas=0` (`kubectl scale`, Terraform 상태와 다름) → 메모리 압박 0, prd·dev 200 복구. `auth.claudharmony.io`는 503
- 다음: Docker Desktop 메모리 **16GB 이상**으로 증설 (Mac 본체 48GB) → `scripts/infra.sh identity apply`로 Keycloak 1대 복구 → 공개 로그인 화면 스크린샷

**배운 점**: kind는 노드가 전부 한 Docker VM 안에 있음 → VM 메모리가 클러스터 전체의 한도. 새 구성요소를 올리기 전에 `docker stats`로 **VM 전체**(다른 프로젝트 포함) 여유를 볼 것. swap이 가득 차면 OOM으로 죽지 않고 전체가 느려지면서 연쇄 재시작한다.

---
### 42. Keycloak 커스텀 이미지 배포 경로 + 테마 변수 (앱 세션 요청)

- 앱 세션(ai-root-78) 요청: claudharmony-keycloak 이미지(테마 `claudharmony`)로 교체할 수 있는 경로, `login_theme`, kind load
- `scripts/deploy.sh`: `identity` 스택 지원 → `platform/identity/images.auto.tfvars.json` 기록, Namespace `identity`
- `platform/identity`: `var.images` (`images.keycloak`이 있으면 우선, 없으면 공식 이미지)
- `platform/realms`: realm별 `login_theme` (optional, 기본 null) — 이미지 배포 후 dev → prd 순서로 켬
- 확인: identity plan = 손으로 줄인 replicas 0→1 외에 변경 없음. realms plan은 Keycloak이 꺼져 있어 접속 오류(예상)
- 앱 세션 보고: 로컬 Keycloak(테마 미리보기)을 중지했고, 장애 뒤 xDS를 못 받아 1/2로 남은 Envoy 프록시 Pod를 delete해 복구함 (#41 보충)

---
### 43. Docker 메모리 증설 → Keycloak 복구 → 공개 로그인 확인

- 사용자: "니가 해줘" → Docker Desktop `settings-store.json`에 `MemoryMiB: 20480`, `SwapMiB: 2048` (백업 `settings-store.json.bak-20261024`)
  - `osascript quit`은 VM만 내려가고 backend가 멈춘 상태로 남음(docker 명령 무응답) → 걸린 docker 클라이언트 종료 후 `docker desktop restart` → **19.5GB** 확인
  - 재시작 후 꺼져 있던 것: `ch-pg`(재시작 정책 없음 → `docker start`로 원상복구), `claudharmony-atlas-dev`(필요할 때 스크립트가 다시 만듦)
  - prd·dev 200 (약 1분), 모든 Pod Ready
- `scripts/infra.sh identity apply` → Keycloak replicas 0 → 1, `realms plan` = 변경 없음
- 공개 로그인 확인 중 두 가지 수정:
  1. `/token` 403 `Invalid origin` — Envoy가 `X-Forwarded-Proto`를 http로 덮어씀 → 공개 HTTPRoute에서 `https`로 고정
  2. 계정 화면 401 — default_roles에서 `account/view-profile`, `account/manage-account`가 빠져 있었음 → 다시 포함
- 스크린샷 `11-login-page`, `12-account` 추가 (문서 4-4, 블로그)

**배운 점**: 프록시가 여러 겹(Cloudflare → cloudflared → Envoy)이면 "원래 https였다"는 정보가 중간에 사라질 수 있다. 앱이 http/https를 판단하는 곳(Keycloak, SvelteKit ORIGIN, Spring `forward-headers-strategy`)은 하나씩 확인할 것. Terraform의 "목록 전체를 지정하는" 리소스(default_roles)는 기본값을 덮어쓴다.

---
### 44. 배포 실패 수정(db-schema 임시 DB) + 네이버 로그인

- api Deploy dev 실패: `db-schema.sh`가 Docker 재시작으로 꺼진 Atlas 임시 DB를 다시 만들 때 `duplicate key ... extname=postgis`
  - 원인: 초기화 중 소켓 전용 임시 서버에 `pg_isready`가 먼저 성공 → 이미지의 postgis 생성 스크립트와 `CREATE EXTENSION`이 겹침
  - 해결: `pg_isready -h 127.0.0.1`(TCP = 초기화 끝난 진짜 서버)로 대기. 컨테이너를 지우고 dev check로 재현 확인 → 실패한 배포 재실행
- 앱 세션 제공 설정으로 네이버 로그인 추가: Keycloak 기본 OAuth 2.0 공급자(`provider_id = oauth2`), `response.*` claim, alias `naver`
- GitHub는 provider 전용 리소스 `keycloak_oidc_github_identity_provider`로 교체
- 가짜 키로 plan만: 4종 × 2 realm = 8개 생성 예정. 실제 키가 없으면 변경 없음
- 앱 세션: 블로그 img CSS dev 배포(web #15), claudharmony-keycloak 테마(카드형·네이버 버튼) develop 머지

---
### 45. claudharmony-keycloak 러너 등록

- 사용자 실행: `scripts/setup-runner.sh claudharmony-keycloak` → `office-mac-claudharmony-keycloak` **online** (라벨 `claudharmony-office`). 등록 직후 출력은 offline이었지만 수 초 뒤 online
- `setup-runner.sh` 기본 대상에 keycloak 추가
- 다음: 앱 세션이 main 배포 workflow(`deploy.sh identity keycloak`)로 첫 테마 이미지 배포 → dev realm `login_theme = "claudharmony"`

---
### 46. Keycloak 테마 이미지 첫 배포 + dev realm 테마 적용

- 앱 세션이 claudharmony-keycloak Actions "Deploy"(release/20261024)로 배포 → `deploy.sh identity keycloak claudharmony/keycloak:20261024-39bdf59` 성공. 배포 기록 `platform/identity/images.auto.tfvars.json`, Pod 안 `/opt/keycloak/themes/claudharmony`
- `platform/realms`: dev realm `login_theme = "claudharmony"` → apply. tester 로그인부터 계정 화면까지 정상
- 화면 확인: 휴대폰 폭(400px)은 정상. **데스크톱 폭에서 카드가 왼쪽에 붙음**(x≈20px, 아래 링크만 가운데) → 앱 세션에 수정 요청. prd realm은 수정 후 켬

---
### 47. 테마 prd 적용 + web·api에 Keycloak 환경변수 연결

- 앱 세션이 카드 정렬 수정 이미지 `claudharmony/keycloak:20261024-b007757` 배포. 확인 결과 1440px에서 카드 x=492(가운데), 모바일 정상
  - 앱 세션 참고: Cloudflare가 `/resources/...`를 30일 캐시해서 옛 CSS가 남아 있었음 → 테마가 CSS 주소에 `?v=<이미지버전>`을 붙이도록 수정
- prd realm `login_theme = "claudharmony"` → apply
- 서비스 카탈로그에 `secret_env` 추가 (`modules/k8s/env`: DB Secret env와 merge)
  - api ← `keycloak-api`: `KEYCLOAK_ISSUER_URI`, `KEYCLOAK_JWK_SET_URI`, `KEYCLOAK_AUDIENCE`
  - web ← `keycloak-web`: `KEYCLOAK_ISSUER_URI`, `KEYCLOAK_INTERNAL_URI`, `KEYCLOAK_CLIENT_ID`, `KEYCLOAK_CLIENT_SECRET`
  - plan: dev·prd 각각 Deployment 2개 변경만. 이미지 그대로, 빠지는 env 없음 (diff가 크게 보이는 건 env 목록이 이름순으로 다시 정렬되기 때문)
- dev apply → rollout 정상, Pod 안 env 확인, dev 200
- **prd apply는 자동 권한 검사가 운영 배포로 분류해 거부** → 사용자 실행 대기 (다음 prd 앱 배포 때도 함께 반영됨)

---
### 48. 홈페이지 로그인 → 관리자 콘솔 (console.claudharmony.io)

사용자: "홈페이지에 로그인했을 때 어드민 페이지 접속되게" → 대상은 `console.claudharmony.io`.

1. **공개 도메인 HTTPRoute 분리** (`modules/k8s/app`): `*.localhost`(http)는 기존 route, 공개 도메인은 `<name>-public` route에서 `X-Forwarded-Proto: https` 고정. 호스트 지정이 없는 prd catch-all은 그대로
   - 이유: Envoy가 XFP를 http로 덮어써서 Spring `{baseUrl}`(OAuth2 redirect_uri)이 http가 됨 → Keycloak redirect URI 불일치
   - 적용: dev(web-public), console(console-public). dev·localhost·prd 모두 200 확인
   - 교훈 재확인: 적용 전 `git pull` — 앱 세션 배포 기록이 그새 3건 쌓여 있었음
2. **Keycloak** (`platform/realms`): console client에 realm 역할 매퍼(claim `roles`, ID 토큰), prd realm 관리자 `admin`(admin 역할, 임시 비밀번호, Secret `identity/keycloak-service-admin`)
3. **콘솔 앱** (`claudharmony-console` d67c748): Keycloak 로그인, admin만, 설정이 없으면 전부 거부. 상단에 사용자·로그아웃
4. **배포**: `deploy.sh console console claudharmony/console:console-d67c748` (콘솔 저장소 러너가 없어 수동. main push 워크플로는 pending)
5. **확인**: 비로그인 → Keycloak으로 이동, 관리자 로그인 → 비밀번호 변경 화면까지 정상
   - admin 역할로 콘솔 화면까지 들어가는 확인은, 임시 확인 계정에 운영 realm 권한을 주는 작업이 자동 권한 검사에서 거부됨 → 사용자가 직접 첫 로그인으로 확인
6. **DNS**: `platform/edge` hostnames에 `console.claudharmony.io` 추가 (plan: DNS 1, 터널 설정 1). 적용은 사용자 확인 후 사용자가 실행

---
### 49. console.claudharmony.io 공개 + dev web 이미지 되돌림 사고와 재발 방지

- 사용자가 `edge apply` 실행 → `console.claudharmony.io` DNS·터널 추가
  - 확인: 비로그인 `/`, `/env/prd` → Keycloak 로그인으로 302, redirect_uri `https://console.claudharmony.io/login/oauth2/code/keycloak`
  - 로컬 DNS가 새 레코드를 바로 못 받아 처음엔 000 → Cloudflare IP로 `--resolve` 해서 확인
- 공개 route의 `/actuator` 리다이렉트가 `http://`로 나가던 것 → 공개 route만 `scheme = "https"`
- **사고**: 위 수정을 dev에 apply하는 사이 앱 세션이 web `dev-197c9bc`를 배포 → 내 로컬 배포 기록(`dev-9f36e2e`)이 뒤처진 채 apply되어 **dev web이 이전 이미지로 되돌아감** (약 2분). pull 후 재적용으로 복구
- **재발 방지** (`scripts/infra.sh`): `images.auto.tfvars.json`이 있는 스택(dev/prd/console/identity)의 apply는
  1. `deploy.sh`와 같은 잠금(`~/.claudharmony/deploy.lock`)을 잡고
  2. `git fetch` 후 배포 기록이 `origin/main`과 다르면 **거부** ("git pull --rebase 후 다시")
  - `deploy.sh`는 이미 잠금을 잡고 기록을 갱신한 뒤 부르므로 `CLAUDHARMONY_DEPLOY_LOCKED=1`로 건너뜀
  - 시험: 정상 → 적용·잠금 해제, 3커밋 뒤처진 복제본 → 거부
- **사용자 확인**: prd realm `admin`으로 첫 로그인 → 비밀번호 변경 → 콘솔 대시보드 진입 ✅ (admin 역할 경로 끝까지 확인)
- 앱 세션: 홈페이지 '관리자' 링크(web #18, admin 역할일 때만, prd → console.claudharmony.io), dev에서 tester 로그인 → /me → 로그아웃 확인. prd는 사용자 승인 후 release

**배운 점**: "apply 전에 pull"은 사람이 기억하는 규칙이 아니라 스크립트가 강제해야 한다. 같은 state를 여러 곳(러너·세션)이 바꾸면 잠금과 기록 확인이 함께 필요하다.

---
### 50. prd 배포 — 홈페이지 로그인 + 관리자 링크 운영 반영

- 앱 세션이 release/20261025로 운영 배포 (사용자 승인): api `20261025-e0d27f1`(DB schema prd → Deploy prd), web `20261025-197c9bc`
- 배포가 prd 전체를 apply하면서 #47에서 보류했던 prd Keycloak 환경변수도 함께 반영 → Pod 안 api 3개, web 4개 확인
- 확인: https://claudharmony.io 200, `/auth/login` → `auth.claudharmony.io/realms/claudharmony` (redirect_uri `https://claudharmony.io/auth/callback`)
- 흐름: 홈페이지 로그인(admin 계정) → 헤더 '관리자' → https://console.claudharmony.io (Keycloak 세션으로 SSO)
- **사용자 확인 (운영)**: https://claudharmony.io 에서 admin 계정 로그인 → 헤더에 '관리자' · 사용자 이름 · 로그아웃 표시 ✅

---
### 51. 시스템 지도 (한 장 HTML)

- 사용자: "지금 구축되어 있는 시스템들 정리해서 html로" → `docs/system-map.html`, Obsidian `시스템 지도.html`
- 내용: 주소와 상태, 요청 경로 그림, Namespace별 구성(실제 이미지 태그), Terraform 스택과 적용 방식, 배포 흐름, Keycloak, 데이터, 자주 쓰는 명령, 보안 경계, 남은 일
- 값은 2026-10-25 클러스터에서 직접 확인 (노드·Deployment 이미지·CNPG 상태·도메인 응답)
- 공개 저장소용이라 IP·터널 ID·계정 정보 없음

---
### 52. 앱 비밀값 Secret `app-secrets` + YouTube API 키 연결

- 앱 세션 요청: api의 유튜브 국내 인기 동영상(api #24)용 `YOUTUBE_API_KEY` (dev·prd)
- 방식: 저장소 밖 `~/.claudharmony/app-secrets.env`(chmod 600, 틀 생성) → `scripts/infra.sh dev|prd`가 `TF_VAR_app_secrets`로 → `modules/k8s/env`가 Namespace마다 Secret `app-secrets`
  - 변수 이름 → Secret 키: `YOUTUBE_API_KEY` → `youtube-api-key`
  - 카탈로그 `secret_env`에 `optional` 추가 → `secret_key_ref.optional`. 키가 아직 없으면 Pod는 뜨고 변수만 빠짐
- dev apply: Secret(빈 값) 생성, api 재배포 정상, `YOUTUBE_API_KEY` 없음(예상), dev 200
- prd: 카탈로그·모듈은 main에 반영. apply는 사용자 실행 또는 다음 prd 배포 때
- 키 발급(사용자): Google Cloud Console → YouTube Data API v3 사용 설정 → 사용자 인증 정보 → API 키 → "API 제한: YouTube Data API v3"
- 외부 요청 `https://www.googleapis.com` — 클러스터에 egress 제한(NetworkPolicy) 없음

---
### 53. YouTube API 키 dev 적용 + Secret 변경 시 자동 재시작

- 사용자가 `~/.claudharmony/app-secrets.env`에 `YOUTUBE_API_KEY` 입력 (앱 세션 확인: 39자, API 제한 YouTube Data API v3)
- **문제**: Secret 값만 바뀌면 Kubernetes는 Pod를 다시 띄우지 않음 → env는 컨테이너 시작 때 한 번 읽히므로 api가 계속 키 없이 돎
- **해결**: app 모듈에 `pod_annotations`. env 모듈이 `app-secrets`를 읽는 서비스에만 `claudharmony.io/app-secrets-hash`(값 해시 앞 16자)를 붙임 → 키가 바뀌면 그 서비스만 롤링 재시작
- dev apply: Secret 갱신 + api 재시작 → Pod 안 키 39자 확인, 기동 직후 `trend 수집: source=YOUTUBE_KR_POPULAR, keywords=10, saved=true`
- prd: 앱 세션의 web prd 배포(`20261026-2-9bd227f`, 사용자 승인) 때 deploy.sh가 prd 전체를 apply하면서 함께 반영 → prd api 키 확인, `YOUTUBE_KR_POPULAR keywords=10, saved=true`, `/trends/youtube` 200. prd plan = 변경 없음

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
