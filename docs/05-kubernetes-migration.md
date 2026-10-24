# 05. Kubernetes 로 전환하기

**가능하다.** 처음부터 그걸 고려해 "무엇을(서비스 카탈로그)" 과 "어떻게(모듈 구현)" 를 분리해 두었다.

## 무엇이 그대로이고 무엇이 바뀌나

| 계층 | Docker (지금) | Kubernetes (이후) | 변경 여부 |
|------|---------------|-------------------|-----------|
| 서비스 카탈로그 JSON | `services.auto.tfvars.json` | 동일 | **그대로** |
| 어드민 콘솔 API | 카탈로그 수정 + plan/apply | 동일 | **그대로** |
| network 모듈 | docker_network | Namespace (+ NetworkPolicy) | 구현 교체 |
| app-service 모듈 | docker build + container | 레지스트리 push + Deployment + Service | 구현 교체 |
| reverse-proxy 모듈 | nginx 컨테이너 | ingress-nginx + Ingress 리소스 | 구현 교체 |
| 외부 노출 | 공유기 → Mac:80 | 공유기 → 노드 NodePort/LoadBalancer(MetalLB) | 포워딩 대상만 변경 |

## 전환 방식

```
modules/
├── docker/        # 지금 modules/* 를 여기로
│   ├── network  app-service  reverse-proxy
└── k8s/           # 같은 입력 변수 / 같은 출력(upstream 등)을 갖는 구현
    ├── network  app-service  reverse-proxy
envs/
├── office/        # docker
└── office-k8s/    # 같은 카탈로그, source 만 ../../modules/k8s/*
```

1. 모듈 **입력/출력 인터페이스를 동일하게** 유지 (`name, port, env, route_path …` → `upstream`)
2. 이미지 레지스트리 도입 (로컬 레지스트리 컨테이너 or GHCR) — k8s 는 로컬 이미지 직접 사용이 어려움
3. `envs/office-k8s` 에서 병행 운영 → 검증 후 공유기 포워딩 대상 전환 → docker 환경 destroy

## 클러스터 선택지

| 옵션 | 용도 |
|------|------|
| kind (이 Mac 에 `ch4` 클러스터 이미 있음) | 로컬 실험·모듈 개발 |
| k3s (사무실 미니PC/리눅스 서버) | 사무실 상시 운영 — 가볍고 Traefik/ServiceLB 내장 |
| EKS / GKE | 실제 클라우드로 이전 시. 모듈만 한 번 더 교체 |
