# Claud Harmony Infra 문서

> **처음이면** → [11. 학습 가이드](11-learning-guide.md) 순서대로, 전체 그림은 [01. 아키텍처](01-architecture.md).

| # | 문서 | 내용 |
|---|------|------|
| 01 | [아키텍처](01-architecture.md) | 전체 구성도 — 시스템·노드·Namespace·요청 흐름·배포 흐름·Terraform 의존·데이터·보안 경계·버전 |
| 02 | [사무실 네트워크](02-office-network.md) | 이중 NAT 토폴로지, 포트포워딩 시도, 터널 |
| 03 | [운영 가이드](03-operations.md) | kubectl, 구성/재구축, 명령어, 서비스 추가, 트러블슈팅 |
| 04 | [어드민 콘솔 로드맵](04-admin-console-roadmap.md) | AWS/GCP 같은 자체 콘솔 설계와 단계별 계획 |
| 05 | [Kubernetes 학습 가이드](05-kubernetes-guide.md) | 우리 클러스터로 배우는 K8s — 개념 · 코드 위치 · 실습 명령 |
| 06 | [CI/CD](06-cicd.md) | 브랜치 전략(develop→dev, release→prd), 파이프라인, 러너 |
| 07 | [작업 기록](07-worklog.md) | 단계별 작업 · 문제 · 원인 · 해결 |
| 08 | [도메인 연결](08-domain.md) | claudharmony.io + Cloudflare Tunnel — 설정 순서, 토큰 권한, 트러블슈팅 |
| 09 | [데이터베이스](09-database.md) | PostgreSQL 18 + PostGIS (CloudNativePG), 계정·접속(db.sh), 데이터 플랫폼 로드맵 |
| 10 | [관리자 콘솔](10-console.md) | 조회 화면, 구조, 최소 권한(RBAC), Access 보호, 로드맵 |
| 11 | [학습 가이드](11-learning-guide.md) | 컨테이너 → 클러스터 → 워크로드 → Gateway → 외부 공개 → Terraform → DB → 인증 → CI/CD → 운영 → 장애 사례, 단계별 확인 명령·실습 |
| 12 | [인증 서버](12-identity.md) | Keycloak — 개념(OIDC·realm·client), 공개 범위, Terraform 두 스택, 스크린샷, 앱 연동 Secret 계약, 소셜 로그인 |

한 장 요약: [`system-map.html`](system-map.html) — 주소·요청 경로·Namespace·스택·배포·로그인·데이터·보안 경계

브라우저로 보기: [`index.html`](index.html) — `python3 scripts/build_docs.py` 로 생성
Obsidian 동기화: `python3 scripts/sync_obsidian.py`
