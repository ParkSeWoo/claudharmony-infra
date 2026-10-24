# Claud Harmony Infra 문서

| # | 문서 | 내용 |
|---|------|------|
| 01 | [아키텍처](01-architecture.md) | K8s 구성도, 3단계 구조, 클라우드 개념 매핑, 버전, 설계 결정 |
| 02 | [사무실 네트워크](02-office-network.md) | 이중 NAT 토폴로지, 포트포워딩 시도, 터널 |
| 03 | [운영 가이드](03-operations.md) | kubectl, 구성/재구축, 명령어, 서비스 추가, 트러블슈팅 |
| 04 | [어드민 콘솔 로드맵](04-admin-console-roadmap.md) | AWS/GCP 같은 자체 콘솔 설계와 단계별 계획 |
| 05 | [Kubernetes 학습 가이드](05-kubernetes-guide.md) | 우리 클러스터로 배우는 K8s — 개념 · 코드 위치 · 실습 명령 |
| 06 | [CI/CD](06-cicd.md) | 브랜치 전략(develop→dev, release→prd), 파이프라인, 러너 |
| 07 | [작업 기록](07-worklog.md) | 단계별 작업 · 문제 · 원인 · 해결 |
| 08 | [도메인 연결](08-domain.md) | claudharmony.io + Cloudflare Tunnel — 설정 순서, 토큰 권한, 트러블슈팅 |
| 09 | [데이터베이스](09-database.md) | PostgreSQL 18 + PostGIS (CloudNativePG), 계정·접속(db.sh), 데이터 플랫폼 로드맵 |

브라우저로 보기: [`index.html`](index.html) — `python3 scripts/build_docs.py` 로 생성
Obsidian 동기화: `python3 scripts/sync_obsidian.py`
