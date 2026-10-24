# 02. 사무실 네트워크 구성

> 이 저장소는 **public** 입니다. 실제 공인 IP / MAC 주소는 여기 적지 않고 `<PUBLIC_IP>`, `<MAC>` 으로 표기합니다.
> 실제 값은 개인 Obsidian 노트(`클라우드하모니/인프라 구성/02 사무실 네트워크`)에 있습니다.

## 토폴로지 — 이중 NAT

```mermaid
flowchart TB
    INET((인터넷))
    subgraph UP[상위망 192.168.75.0/24]
      GNT[GNT2400 공유기<br/>WAN: 공인 IP<br/>LAN: 192.168.75.1<br/>관리페이지 :80]
    end
    subgraph OFFICE[사무실 LAN 192.168.45.0/24]
      SK[SK브로드밴드 GW-ME611R<br/>WAN: 192.168.75.142 (DHCP)<br/>LAN: 192.168.45.1]
      MAC[MacBook Pro M4 Max<br/>192.168.45.214 · Wi-Fi 2.4G<br/>Docker Desktop · nginx:80]
    end
    INET --- GNT --- SK
    SK -- Wi-Fi --- MAC
```

> 공유기가 **2단**이다. 외부 공개하려면 **두 공유기 모두** 포트포워딩이 필요하다.
> (처음엔 공인 IP:80 에서 로그인 화면이 보여 단일 NAT 로 오판했는데, 그건 상위 GNT2400 의 관리페이지였다.)

## 현재 값 (2026-10-24 측정)

| 항목 | 값 | 비고 |
|------|----|------|
| 서버 호스트 | MacBook Pro (Apple M4 Max, 48GB) | macOS 15.5 |
| 서버 LAN IP | `192.168.45.214` (DHCP) | **DHCP 고정 할당 필요** |
| 서브넷 | `192.168.45.0/24` (255.255.255.0) | |
| 1차 공유기 (사무실) | SK GW-ME611R, LAN `192.168.45.1`, WAN `192.168.75.142` | WAN IP 는 상위 DHCP → 고정 필요 |
| 2차 공유기 (상위) | GNT2400, LAN `192.168.75.1` | 공인 IP 보유. 관리페이지가 공인 IP:80 에서 응답 |
| DNS | ISP 제공 DNS 2개 | |
| 공인 IP | `<PUBLIC_IP>` (상위 GNT2400 WAN) | **이중 NAT** → 포트포워딩 2번 |
| 공인 IP 성격 | 유동 IP 일 가능성 높음 | 바뀌면 접속 주소도 바뀜 → DDNS 권장 |
| DHCP 임대 | 6시간 | |
| macOS 방화벽 | 꺼짐 | |
| Docker Desktop | 포트 80 → nginx | 다른 프로젝트가 5432/5433/6333/8080 사용 중 (충돌 없음) |

## 외부 접근을 위한 공유기 설정 (수동 작업)

공인 IP 의 **80 포트는 공유기 관리 페이지가 사용 중**이라 그대로 포워딩할 수 없다. 두 가지 중 하나를 선택:

### 포트포워딩 (2단)

| 공유기 | 프로토콜 | 외부 포트 | 내부 IP | 내부 포트 | 상태 |
|--------|----------|-----------|---------|-----------|------|
| GNT2400 (192.168.75.1) | TCP | `8888` | `192.168.75.142` | `8888` | ⏳ 관리자 계정 필요 |
| SK GW-ME611R (192.168.45.1, NAT/라우터 → 포트포워드) | TCP | `8888` | `192.168.45.214` | `80` | ✅ 2026-10-24 |

→ 접속 주소: `http://<PUBLIC_IP>:8888/`

외부 80 은 GNT2400 관리페이지가 점유 중이라 8888 사용. GNT2400 의 원격 관리는 끄는 것을 권장.

### 현재 외부 공개 방식: Cloudflare Quick Tunnel (2026-10-24 ~)

GNT2400 관리자 계정이 없어 포트포워딩 불가 → 터널로 공개 중.

```
외부 → https://<랜덤>.trycloudflare.com → Cloudflare → tunnel 컨테이너 → nginx:80 → hello-app
```

| 항목 | 내용 |
|------|------|
| 컨테이너 | `tunnel` (`cloudflare/cloudflared:2025.10.0`, `--restart unless-stopped`, 네트워크 `claudharmony-office`) |
| 현재 주소 확인 | `scripts/infra.sh url` |
| 주의 | 컨테이너 재시작 시 **주소가 바뀜**. 주소를 아는 누구나 접속 가능 |
| 관리 | 현재 `docker run` 으로 수동 기동 (Terraform 미관리). `modules/tunnel` 은 준비됨 → `envs/office/main.tf` 에 연결 예정 |
| 고정 주소 | 도메인 구매 → Cloudflare named tunnel 로 전환 |

### 상위 공유기 권한이 없을 때

Cloudflare Tunnel (`cloudflared tunnel --url http://localhost:80`) — Mac 에서 바깥으로 연결하므로 NAT 단수·포트포워딩과 무관.

$1

1. **DHCP 고정 할당 (2곳)**: SK 공유기에서 Mac `<MAC>` → `192.168.45.214`, GNT2400 에서 SK WAN MAC → `192.168.75.142`. 안 하면 IP 가 바뀌어 포워딩이 끊김.
2. **Mac 절전 방지**: 노트북이 잠들면 서비스도 내려감.
   ```bash
   sudo pmset -c sleep 0 disksleep 0   # 전원 연결 시 잠자기 끄기
   ```
   Docker Desktop → Settings → General → *Start Docker Desktop when you sign in* 체크.
3. **(가능하면) 유선 연결**: 현재 Wi-Fi. 서버 용도면 유선이 안정적.

### 검증

```bash
scripts/infra.sh check                     # 사무실 안: localhost / LAN 확인
curl http://<PUBLIC_IP>:8888/              # 사무실 밖(휴대폰 LTE 등)에서 확인
```

> 사무실 내부에서 공인 IP 로 접속하면 공유기의 NAT loopback(헤어핀) 지원 여부에 따라 실패할 수 있다. 외부 검증은 반드시 **사무실 밖 네트워크**에서.

## 도메인 구매 후

1. DNS A 레코드 → `<PUBLIC_IP>` (유동이면 Cloudflare DDNS 등)
2. `envs/office/terraform.tfvars` 의 `server_name = "도메인"`
3. TLS: 443 포워딩 + Let's Encrypt (certbot 컨테이너 or Cloudflare proxy) — `reverse-proxy` 모듈 확장 예정
4. 대안: **Cloudflare Tunnel** — 포트포워딩 없이 외부 공개 가능, 공인 IP 노출 없음
