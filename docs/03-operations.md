# 03. 운영 가이드 (Runbook)

## 사전 요구사항

| 도구 | 확인된 버전 |
|------|-------------|
| Terraform | 1.15.x |
| Docker Desktop | 27.x (`unix:///var/run/docker.sock`) |
| kreuzwerker/docker provider | 3.9.x |

JDK 는 호스트에 필요 없음 — 앱은 Docker 멀티스테이지(`gradle:8.14-jdk21` → `eclipse-temurin:21-jre`)로 빌드.

## 처음 구성

```bash
git clone git@github.com:ParkSeWoo/claudharmony-infra.git ~/infra
cd ~/infra
scripts/infra.sh init
scripts/infra.sh apply
scripts/infra.sh check
```

## 자주 쓰는 명령

| 목적 | 명령 |
|------|------|
| 변경 미리보기 | `scripts/infra.sh plan` |
| 적용 | `scripts/infra.sh apply` |
| 상태 | `scripts/infra.sh status` |
| 로그 | `scripts/infra.sh logs hello-app` / `logs nginx` |
| 접속 점검 | `scripts/infra.sh check` |
| 전부 내리기 | `scripts/infra.sh destroy` |
| nginx 실제 설정 보기 | `docker exec nginx cat /etc/nginx/conf.d/default.conf` |

## 서비스 추가하기 (예: `api`)

1. `apps/api/` 에 Dockerfile 이 있는 앱 추가
2. `envs/office/services.auto.tfvars.json` 에 한 줄 추가:
   ```json
   "api": { "source_dir": "apps/api", "port": 8080, "route_path": "/api/" }
   ```
3. `scripts/infra.sh apply` → 이미지 빌드, 컨테이너 생성, nginx 라우트 자동 추가

`route_path` 를 생략하면 외부에 노출되지 않는 **내부 전용 서비스**가 된다.

## 앱 코드 수정 → 배포

소스 해시가 이미지 태그이므로 코드만 고치고 `apply` 하면 된다. 변경이 없으면 아무것도 하지 않는다.

## Git 워크플로

```bash
git checkout -b feat/xxx
scripts/infra.sh plan          # plan 결과를 PR 에 붙인다
git commit / push → PR → merge
git checkout main && git pull && scripts/infra.sh apply
```

커밋하지 않는 것: `*.tfstate*`, `.terraform/`, `*.tfvars` (예시 파일 제외) — `.gitignore` 로 처리됨.

## 트러블슈팅

| 증상 | 원인 / 조치 |
|------|-------------|
| `Error running legacy build ... 403` | provider 내장 빌드 문제. 이 저장소는 이미 CLI 빌드 사용 중 |
| 502 Bad Gateway | 앱 기동 중(약 10~20초). `scripts/infra.sh status` 에서 `healthy` 확인 |
| `port is already allocated` (80) | 다른 프로세스가 80 사용. `lsof -nP -iTCP:80 -sTCP:LISTEN` / `public_port` 변경 |
| 외부에서 안 됨, 내부는 됨 | 공유기 포트포워딩·DHCP 고정·공인 IP 변경 여부 확인 (02 문서) |
| 공인 IP 로 접속하면 공유기 로그인 화면 | 80 이 공유기 관리페이지로 감. 02 문서 방법 A/B |
| plan 에 계속 변경이 뜸 | Docker 기본값 드리프트. 해당 속성을 모듈에 명시 (예: `memory_swap`) |
