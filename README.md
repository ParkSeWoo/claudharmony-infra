# claudharmony-infra

Claud Harmony 사무실 인프라 — **Kubernetes v1.37 (kind) + Envoy Gateway + Terraform**.

```
https://claudharmony.io → Cloudflare Tunnel → Gateway(Envoy) → HTTPRoute → Service → Pod (dev / prd Namespace)
```

## 빠른 시작

```bash
scripts/infra.sh cluster apply   # 1단계: kind 클러스터
scripts/infra.sh gateway apply   # 2단계: Envoy Gateway
scripts/infra.sh edge apply      # 2.5단계: 도메인 터널 + DNS (docs/08-domain.md)
scripts/infra.sh dev apply       # 3단계: dev 환경
scripts/infra.sh prd apply       #        prd 환경
scripts/infra.sh prd check       # https://claudharmony.io 확인
```

- 앱 배포: [claudharmony-homepage](https://github.com/ParkSeWoo/claudharmony-homepage) — `develop` push → dev 자동, `release/YYYYMMDD` → prd 수동
- 인프라 변경: 이 저장소 `main` 머지 → gateway/dev 자동 적용, prd/cluster 수동
- 문서: [docs/](docs/README.md) — 아키텍처 · 네트워크 · 운영 · 어드민 콘솔 · **K8s 학습 가이드** · CI/CD · 작업 기록
