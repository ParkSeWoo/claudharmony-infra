# 03. 운영 가이드 (Runbook)

## 사전 요구사항

| 도구 | 버전 | 설치 |
|------|------|------|
| Docker Desktop | 27.x | 메모리 8GB 이상 권장 |
| kind | v0.33.0 | `brew install kind` |
| kubectl | v1.37.x | `brew install kubernetes-cli` |
| helm | v4.x | `brew install helm` (Terraform helm provider 가 쓰지만 디버깅용) |
| Terraform | 1.15.x | `brew install terraform` |
| gh | 로그인 + `repo`, `workflow` 권한 | `gh auth login`, `gh auth refresh -s workflow` |

## kubectl 쓰는 법

이 클러스터는 **전용 kubeconfig** 를 쓴다 (기본 `~/.kube/config` 를 건드리지 않음).

```bash
export KUBECONFIG=~/.claudharmony/kubeconfig     # 터미널마다 한 번
kubectl get nodes
# 또는 매번
kubectl --kubeconfig ~/.claudharmony/kubeconfig get nodes
```

`~/.zshrc` 에 넣어두면 편하다 (2026-10-24 적용됨, 백업 `~/.zshrc.bak-20261024`):
```bash
# 여러 kubeconfig 를 합쳐서 사용 — kubectl/k9s 에서 컨텍스트 전환
export KUBECONFIG="$HOME/.claudharmony/kubeconfig:$HOME/.kube/config:$HOME/.lima/k3s/copied-from-guest/kubeconfig.yaml"
alias k9ch='k9s --kubeconfig ~/.claudharmony/kubeconfig --context kind-claudharmony'
alias kch='kubectl --kubeconfig ~/.claudharmony/kubeconfig --context kind-claudharmony'
```

### k9s

예전에는 `KUBECONFIG` 가 lima k3s 파일 하나만 가리켜서 k9s 에 아무 클러스터도 안 보였다. 위처럼 합친 뒤:

- 셸 설정과 무관하게 보이도록 `~/.kube/config` 에도 `kind-claudharmony` 를 합쳐 넣고 기본 컨텍스트로 지정 (백업 `~/.kube/config.bak-20261024`, 이전 기본은 `kind-ch4`)
- ⚠️ `cluster apply` 로 클러스터를 **재생성하면** 인증서가 바뀐다 → 다시 합치기:
  `KUBECONFIG=~/.kube/config:~/.claudharmony/kubeconfig kubectl config view --flatten > /tmp/k && mv /tmp/k ~/.kube/config`
- 이미 열려 있던 터미널은 `source ~/.zshrc` 후 사용

| 입력 | 동작 |
|------|------|
| `k9s` → `:ctx` | 클러스터 전환 (`kind-claudharmony`, `kind-ch4`) |
| `k9ch` | 바로 claudharmony |
| `:ns` → `prd` | 네임스페이스 |
| `:deploy` `:pod` `:svc` `:httproute` | 리소스 |
| 파드에서 `l` / `s` | 로그 / 셸 |
| `0` | 전체 네임스페이스 |

## 처음부터 구성 (새 Mac / 재구축)

```bash
git clone https://github.com/ParkSeWoo/claudharmony-infra.git ~/infra && cd ~/infra

scripts/infra.sh cluster apply     # 1단계: kind 클러스터 (~1분)
scripts/infra.sh gateway apply     # 2단계: Envoy Gateway (~30초)

# 3단계: 앱 이미지가 있어야 한다 → 앱 저장소에서 빌드 후 deploy.sh 가 kind load + apply
#   (CI 가 해주므로 보통은 develop 에 push 하면 끝)
scripts/infra.sh dev apply
scripts/infra.sh prd apply

scripts/setup-runner.sh            # GitHub Actions self-hosted runner 등록
```

## 자주 쓰는 명령

| 목적 | 명령 |
|------|------|
| 변경 미리보기 | `scripts/infra.sh dev plan` |
| 적용 | `scripts/infra.sh dev apply` |
| 상태 | `scripts/infra.sh dev status` / `cluster status` / `gateway status` |
| 로그 | `scripts/infra.sh dev logs hello-app` / `logs tunnel` |
| 외부 주소 | `scripts/infra.sh prd url` → https://cloudharmony.io |
| 접속 점검 | `scripts/infra.sh prd check` |
| 현재 배포 버전 | `curl http://localhost/version` , `curl http://dev.localhost/version` |
| 로그인 서버 | 관리 콘솔 http://auth.localhost/admin/ (계정 `claudharmony-admin`, 비밀번호는 `kubectl -n identity get secret keycloak-admin -o jsonpath='{.data.password}' \| base64 -d \| pbcopy`) — [인증 서버](12-identity.md) |
| DB 접속 | `scripts/db.sh up` 한 번 → `scripts/db.sh psql dev` / IntelliJ·TablePlus 는 `127.0.0.1:15432(dev)·25432(prd)` — [데이터베이스](09-database.md) |
| Pod 안 들어가기 | `kubectl -n dev exec -it deploy/hello-app -- bash` |
| 롤백 (이전 ReplicaSet) | `kubectl -n prd rollout undo deploy/hello-app` → **이후 images.auto.tfvars.json 도 맞춰야 함** (안 그러면 다음 apply 때 되돌아감) |

정석 롤백은 `envs/prd/images.auto.tfvars.json` 의 태그를 이전 값으로 바꿔 커밋하고 `scripts/infra.sh prd apply`.

## 서비스 추가하기 (예: `api`)

1. 새 앱 저장소 — `claudharmony-api`(Spring) 또는 `claudharmony-web`(Node) 의 `Dockerfile`, `.github/workflows/*` 를 복사하고 서비스 이름만 변경
2. `envs/dev/services.auto.tfvars.json`, `envs/prd/services.auto.tfvars.json` 에 추가:
   ```json
   "api": { "port": 8080, "route_path": "/api", "replicas": 1, "memory_mb": 512 }
   ```
   `route_path` 를 빼면 **내부 전용** (클러스터 안에서 `http://api.dev.svc.cluster.local` 로만 접근)
3. 앱 저장소 `develop` 에 push → 이미지 빌드 → 카탈로그에 이미지가 기록되며 배포

## 플랫폼 변경

| 작업 | 방법 | 영향 |
|------|------|------|
| Envoy Gateway 업그레이드 | `platform/gateway/variables.tf` 의 `envoy_gateway_version` 변경 → `scripts/infra.sh gateway apply` | 순간 끊김 가능 |
| Kubernetes 업그레이드 | `platform/cluster/variables.tf` 의 `node_image` 변경 → `cluster apply` | ⚠️ kind 는 업그레이드가 아니라 **재생성** → gateway, dev, prd 다시 apply 필요 |
| worker 추가 | `workers` 변경 → `cluster apply` | ⚠️ 재생성 |

## 트러블슈팅

| 증상 | 확인 / 조치 |
|------|-------------|
| `http://localhost/` 응답 없음 | `docker port claudharmony-control-plane` 에 `30080 -> 0.0.0.0:80` 있는지, `kubectl -n envoy-gateway-system get svc claudharmony-gateway` 가 NodePort 30080 / `externalTrafficPolicy: Cluster` 인지 |
| 404 (Envoy) | 라우트 매칭 실패. `kubectl get httproute -A`, Host 헤더 확인 (dev 는 `dev.localhost`) |
| HTTPRoute 가 Gateway 에 안 붙음 | `kubectl -n dev describe httproute hello-app` 의 `Accepted` 조건. Namespace 라벨 `claudharmony.io/gateway-access=true` 확인 |
| Pod `ErrImageNeverPull` / `ImagePullBackOff` | 이미지가 kind 노드에 없음 → `kind load docker-image <image> --name claudharmony` |
| Pod `CrashLoopBackOff` | `kubectl -n dev logs deploy/hello-app --previous` |
| Pod `Running` 인데 `0/1` | readiness probe 실패 → `kubectl -n dev describe pod -l app.kubernetes.io/name=hello-app` 의 Events |
| `OOMKilled` | `memory_mb` 증가 (서비스 카탈로그) |
| 도메인 접속 안 됨 | `kubectl -n edge get pods` (cloudflared 2/2 Ready?), `kubectl -n edge logs deploy/cloudflared` 에 `Registered tunnel connection` 4개, `scripts/infra.sh edge plan` 으로 드리프트 확인 |
| terraform `context "kind-claudharmony" does not exist` | 클러스터가 없음 → `scripts/infra.sh cluster apply` 부터 |
| Docker Desktop 재시작 후 | kind 노드 컨테이너는 자동 재시작됨. 터널 주소는 바뀜 |
| 메모리 부족 (Pending Pod) | `kubectl describe pod` → `Insufficient memory`. Docker Desktop 메모리 늘리거나 다른 클러스터(`ch4`) 정리 |

과거에 실제로 겪은 문제와 해결 과정은 [작업 기록](07-worklog.md) 에 있다.
