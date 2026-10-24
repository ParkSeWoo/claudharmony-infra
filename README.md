# claudharmony-infra

사무실 서버를 Terraform 으로 관리하는 Claud Harmony 인프라 저장소.

```
외부 → 공유기(포트포워딩) → nginx:80 → hello-app (Spring Boot) "안녕하세요 클라우드 하모니"
```

## 빠른 시작

```bash
scripts/infra.sh init
scripts/infra.sh apply
scripts/infra.sh check      # localhost / LAN 응답 확인
```

- 서비스 추가: `envs/office/services.auto.tfvars.json` 수정 후 `apply`
- 문서: [docs/](docs/README.md) — 아키텍처 · 사무실 네트워크 · 운영 · 어드민 콘솔 로드맵 · Kubernetes 전환
