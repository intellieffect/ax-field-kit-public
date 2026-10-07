# 결정 기록 (decisions.md)

1판 2026-10-07 05:1x KST · 조사 워커(AX현장 · 조사·시나리오). 근거는 공식 문서 링크. 근거가 없는 것은 "확인 필요"로 적었다.
비밀값(키·토큰·비밀번호)은 이 문서와 저장소 어디에도 쓰지 않는다.

---

## 1. Claude Code on Windows

**결정: 네이티브 설치(PowerShell 한 줄)를 기본으로 하고, winget을 대안으로 둔다. WSL·npm은 쓰지 않는다.**

| 항목 | 내용 | 출처 |
|---|---|---|
| 공식 권장 | "Native Install (Recommended)" — PowerShell `irm https://claude.ai/install.ps1 \| iex` / CMD `curl -fsSL https://claude.ai/install.cmd -o install.cmd && install.cmd && del install.cmd` | [setup](https://code.claude.com/docs/en/setup) |
| 대안 | `winget install Anthropic.ClaudeCode` — 자동 업데이트 안 됨(`winget upgrade Anthropic.ClaudeCode`) | 같은 곳 |
| npm | `npm install -g @anthropic-ai/claude-code`, Node.js 22+ 필요 → 고객 PC에 Node를 따로 깔아야 하므로 쓰지 않는다 | 같은 곳 |
| 관리자 권한 | 네이티브 설치는 "You do not need to run as Administrator" | 같은 곳 |
| 요구 사항 | Windows 10 1809+ / Server 2019+, RAM 4GB+, x64·ARM64, 인터넷 | 같은 곳 |
| Git for Windows | 선택. 있으면 Bash 도구(Git Bash), 없으면 PowerShell 도구로 명령 실행. → **같이 깔기 권장**(`winget install --id Git.Git -e`) — Claude Code가 git도 쓰게 됨 | 같은 곳 |
| 설치 경로 | `%USERPROFILE%\.local\bin\claude.exe`, 버전 파일 `%USERPROFILE%\.local\share\claude` (제거 명령에서 확인) | 같은 곳(Uninstall 절) |
| PATH | 설치 뒤 **새 터미널**을 열어 `claude --version`. 안 잡히면 "Fix your PATH" 문서 | 같은 곳 |
| 진단 | `claude doctor` (읽기 전용 진단) | 같은 곳 |
| 자격 증명 저장 | `%USERPROFILE%\.claude\.credentials.json` (사용자 프로필 권한) | [authentication](https://code.claude.com/docs/en/authentication) |
| 로그아웃 | Claude Code 안에서 `/logout` | 같은 곳 |
| 제거 | `Remove-Item "$env:USERPROFILE\.local\bin\claude.exe" -Force` + `Remove-Item "$env:USERPROFILE\.local\share\claude" -Recurse -Force`, 설정까지 지우려면 `%USERPROFILE%\.claude`, `%USERPROFILE%\.claude.json` | setup |

### 로그인 계정 선택지 (결정은 담당자)

무료 claude.ai 플랜은 Claude Code 불가. Pro·Max·Team·Enterprise·Console(API) 중 하나 필요 ([authentication](https://code.claude.com/docs/en/authentication)).

| 선택지 | 방식 | 비용 주체 | 장점 | 단점 |
|---|---|---|---|---|
| A. 고객사 자체 계정 (Pro/Max 또는 Team) | `claude` 실행 → 브라우저 로그인 | 고객사 | 계정·데이터 소유가 고객, 철수가 깔끔 | 고객이 오늘 결제·가입해야 함 |
| B. 우리(인텔리이펙트) Team 좌석 1개 배정 | 고객 PC에서 우리 조직 계정으로 로그인 | 우리(서비스 비용에 포함) | 관리·회수 쉬움(좌석 해제) | 좌석 비용, 우리 조직 소속이 됨 — Team 구독 여부 확인 필요 |
| C. Console(API) 키 — 사용량 과금 | Console 초대 → "Claude Code" 역할 → 로그인 | 키 소유자(우리 또는 고객) | 쓴 만큼만, 지출 한도 설정 가능 | 사용량 많으면 비쌀 수 있음, 키 관리 필요 |

`claude setup-token`(1년짜리 토큰)은 무인·CI용이라 사람이 쓰는 고객 PC에는 필요 없다.
금액은 [claude.com/pricing](https://claude.com/pricing) 기준으로 담당자가 확인 — 이 문서에 숫자는 쓰지 않음(확인 필요).

---

## 2. Tailscale 무인 가입

**결정: winget(`Tailscale.Tailscale`) → 실패 시 공식 MSI. `tailscale up --auth-key=file:<임시파일> --unattended`. 키는 현장에서 `Read-Host -AsSecureString`으로 입력받고 즉시 지운다.**

| 항목 | 내용 | 출처 |
|---|---|---|
| 요구 사항 | Windows 10+ / Server 2016+ | [install-windows](https://tailscale.com/kb/1022/install-windows) |
| MSI | `https://pkgs.tailscale.com/stable/#windows` 에서 `.msi`. `msiexec /i <msi>` / 제거 `msiexec /x <msi>`. 속성 `TS_UNATTENDEDMODE=always`, 무음 설치 시 GUI 안 띄우기 `TS_NOLAUNCH=1` | [install-windows-msi](https://tailscale.com/kb/1189/install-windows-msi) |
| winget id | `Tailscale.Tailscale` — 공식 문서에서 직접 확인 못 함(확인 필요, 실패 시 MSI 경로가 있으므로 막히지 않음) | — |
| 관리자 권한 | 설치(서비스 등록)에 필요 — 공식 문서에 명시 문구 못 찾음(확인 필요, 일반적으로 필요) | — |
| CLI 경로 | `C:\Program Files\Tailscale\tailscale.exe` (확인 필요 — 공식 문서 문구 못 봄, 일반 설치 경로) | — |
| 무인 실행 | `--unattended`(Windows 전용): 사용자가 로그아웃해도 계속 연결. 트레이 우클릭 → Preferences → Run unattended 와 같음 | [tailscale up](https://tailscale.com/docs/reference/tailscale-cli/up), [run-unattended](https://tailscale.com/docs/how-to/run-unattended) |
| 키로 가입 | `tailscale up --auth-key=<key>`, 또는 `--auth-key=file:<경로>` (명령줄 기록에 키를 안 남김) | tailscale up · [auth-keys](https://tailscale.com/kb/1085/auth-keys) |

### 사전 인증 키 설정 (관리 콘솔 Settings → Keys, 담당자가 발급)

- **일회용(one-off)**: 한 번 쓰면 자동 폐기 → 고객 PC 1대면 이것. 재사용 키는 "도난 시 위험" (공식 경고).
- **만료**: 1~90일 선택(기본 90). **1일**로 발급. 키가 만료돼도 이미 가입한 기기는 끊기지 않는다.
- **Ephemeral 끔**: 켜면 오프라인 시 기기가 자동 삭제됨 → 퇴근·재부팅마다 사라지므로 **끈다**.
- **Pre-approved 켬**: tailnet에 기기 승인을 켜 둔 경우 승인 생략.
- **Tags**: `tag:ax-field` (또는 고객별 `tag:cust-<고객>`). 태그 기기는 기기 키 만료가 기본 꺼짐 → 장기 원격 유지에 유리. 태그는 policy 파일 `tagOwners`에 먼저 정의해야 함.
- 출처: [auth-keys](https://tailscale.com/kb/1085/auth-keys), [tags](https://tailscale.com/kb/1068/tags)

### 현장 입력 (스크립트에 키를 박지 않음)

```powershell
$sec = Read-Host '인증 키' -AsSecureString     # 화면에 안 보임
# → 평문으로 바꿔 %TEMP% 임시 파일에 쓰고 tailscale up --auth-key=file:<파일> 후 즉시 삭제
```

### ACL로 범위 좁히기 (예시 — 관리 콘솔 Access controls)

고객 PC는 우리 쪽으로 **먼저 접속하지 못하게**, 우리 관리자만 고객 PC의 SSH(22)에 들어가게:

```json
{
  "tagOwners": { "tag:ax-field": ["autogroup:admin"] },
  "grants": [
    { "src": ["autogroup:admin"], "dst": ["tag:ax-field"], "ip": ["tcp:22"] }
  ]
}
```
- 기존 tailnet에 "모두 허용" 규칙(`*`→`*`)이 있으면 고객 PC가 우리 장비 전체에 닿는다 → **현장 전에 기존 policy 확인 필요**. 태그 기기에서 출발하는 grant를 만들지 않으면 고객 PC는 어디에도 접속 못 한다.
- 문법 근거: [tags](https://tailscale.com/kb/1068/tags) (`grants` src/dst/ip 예시). `autogroup:admin` 표기는 확인 필요.

### 녹화 파일 가져오는 경로 (중요)

- **Tailscale SSH 서버는 Windows 미지원**(Linux·macOS만) → [tailscale-ssh](https://tailscale.com/kb/1193/tailscale-ssh)
- **Taildrop은 태그 기기 불가·같은 사용자 기기끼리만** → [taildrop](https://tailscale.com/kb/1106/taildrop)
- → **Windows 내장 OpenSSH 서버**를 켜고, 방화벽은 Tailscale 대역 `100.64.0.0/10`만 허용, 우리 맥에서 `scp`/`rsync`로 당겨 온다. 계정은 고객 Windows 로그인 계정 또는 전용 로컬 계정 + 우리 공개키(`administrators_authorized_keys`) — 확인 필요.
- 차선: SMB 공유(같은 방화벽 제한). 원격 데스크톱(RDP)은 화면 조작용으로만.

### 철수·해지

1. 고객 PC: `tailscale logout` (또는 트레이 → Log out) → 제거 `winget uninstall Tailscale.Tailscale` 또는 `msiexec /x`.
2. 관리 콘솔 Machines → 해당 기기 **Remove** (키 폐기만으로는 기존 기기가 안 끊김 — 공식 문서).
3. Keys → 남은 키 **Revoke** (일회용은 사용 즉시 자동 폐기).

---

## 3. 화면 녹화

**추천: ffmpeg `gdigrab` + PowerShell 감시 스크립트(트레이 아이콘·업무 시간·잠금/자리 비움 정지·창 이름 JSONL·오래된 파일 삭제) + 작업 스케줄러 로그온 트리거.**
**차선: OBS Studio `--startrecording --minimize-to-tray` (작업 스케줄러 로그온 실행).**
(`recorder.ps1`이 추천안 구조)

| 기준 | ffmpeg gdigrab (추천) | ffmpeg ddagrab | OBS Studio (차선) | ShareX | Windows 기본(Game Bar·캡처 도구) |
|---|---|---|---|---|---|
| 사람 조작 없이 백그라운드 | O (콘솔 숨김 실행) | O | O (`--startrecording`) | X — 수동 시작·짧은 클립용 | X — 수동, Game Bar는 앱 1개 창 단위 |
| 로그온 자동 시작 | 작업 스케줄러 | 작업 스케줄러 | 작업 스케줄러/시작프로그램 | 시작프로그램만(녹화는 수동) | 불가 |
| 녹화 중 표시 | 감시 스크립트 트레이 아이콘(빨강/회색) | 같음 | OBS 트레이 아이콘(녹화 중 표시) | 트레이 | 녹화 막대 |
| 초당 1~2장·저해상도 | `-framerate 1` + scale | `framerate=1` | 설정에서 FPS 1 가능(확인 필요: 1fps 안정성) | — | 불가(고정 30/60) |
| 업무 시간·잠금 시 정지 | 스크립트가 시작/정지 | 같음 | 직접 불가(외부 스크립트 + obs-websocket 필요) | 불가 | 불가 |
| 앱·창 이름 기록 | 스크립트가 같이 기록(JSONL) | 같음 | 불가(별도 스크립트) | 불가 | 불가 |
| 분할·자동 삭제 | `-f segment` + 스크립트 보관 기간 삭제 | 같음 | 분할 녹화 있음, 삭제는 외부 | 불가 | 불가 |
| CPU·용량(1fps, 1600px, x264 crf 32) | 낮음. 시간당 **수십~200MB 추정**(정적 화면 많음) — 현장 10분 실측 필요 | GPU 경로로 더 낮음 | 상시 GUI 프로세스, 상대적으로 무거움 | — | — |
| 호환성 | GDI — Windows 대부분·RDP에서도 동작, 모든 모니터를 한 화면으로 | Windows 8+·D3D11 필요, 모니터별, `hwdownload,format=bgra` 필요, 원격 세션·구형 GPU에서 실패 가능 | 넓음 | — | — |
| 설치 크기·권한 | ffmpeg.exe 1개(약 100MB대), 스크립트 폴더만. 작업 스케줄러 등록에 관리자 필요할 수 있음 | 같음 | 설치 수백 MB, 관리자 | — | 내장 |
| 업로드 | 우리 쪽이 Tailscale+SSH로 당김 | 같음 | 같음 | — | — |
| 끄기·제거 | 트레이 → 일시정지/종료, `uninstall.ps1`(작업 삭제+폴더 삭제) | 같음 | OBS 종료·제거 | — | — |
| 라이선스 | FFmpeg LGPL/GPL(winget `Gyan.FFmpeg` 빌드는 GPL) — 내부 도구로 실행만 하므로 배포 문제 없음 | 같음 | GPL-2.0 | GPL-3.0 | — |

**gdigrab을 고른 이유**: 부품이 가장 적고(ffmpeg 1개 + PowerShell 기본 기능), 업무 시간·잠금·창 기록·보관 삭제를 한 스크립트에서 다 할 수 있다. 1fps에서는 gdigrab의 CPU 단점이 거의 없고, ddagrab보다 호환성이 넓다(원격 세션·구형 그래픽). ddagrab은 gdigrab이 검은 화면/높은 CPU를 낼 때의 교체 후보.

참고 명령(공식 예시): `ffmpeg -f gdigrab -framerate 6 -i desktop out.mpg` — [ffmpeg-devices#gdigrab](https://ffmpeg.org/ffmpeg-devices.html#gdigrab). ddagrab은 필터(`-f lavfi -i ddagrab=framerate=1,hwdownload,format=bgra`, 확인 필요) — [ffmpeg-filters#ddagrab](https://ffmpeg.org/ffmpeg-filters.html#ddagrab). OBS 실행 인자 — [OBS launch parameters](https://obsproject.com/kb/launch-parameters).

주의(확인 필요): 화면 잠금·UAC 보안 데스크톱은 gdigrab이 못 찍음(정지 조건이라 문제 없음). 백신(EDR)이 숨김 ffmpeg 상시 실행을 의심할 수 있음 → 현장에서 예외 등록 요청 대비.

### 데이터 처리 한 줄

녹화(초당 1장 영상)와 앱·창 이름 기록은 고객 PC `C:\AxFieldKit\data` 한 곳에만 저장되고 업무 시간(기본 09:00~18:00, 평일)에만 남으며 14일 지나면 자동 삭제된다. 인텔리이펙트 AX 담당자만 Tailscale 암호화 연결로 가져가 업무 분석에 쓴다.

### 정교한 판(이후)

정교한 Windows판은 이후 Tailscale+SSH로 원격 교체.
