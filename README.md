# ax-field-kit

고객사 Windows PC 현장 설치 키트. **설치자는 Claude Code 설치와 로그인까지만 직접 하고, 나머지는 이 폴더를 연 Claude Code 가 `CLAUDE.md` 대로 준비한다.**

## 설치자가 직접 칠 것 (관리자 PowerShell)

1. zip 풀기 (D: 는 USB 드라이브 문자에 맞게 바꾸기):
   ```powershell
   Expand-Archive D:\ax-field-kit.zip C:\ -Force; cd C:\ax-field-kit
   ```
2. Claude Code 공식 설치:
   ```powershell
   irm https://claude.ai/install.ps1 | iex
   ```
   (끝나면 PowerShell 을 닫고 **관리자 PowerShell 을 새로 열어** `cd C:\ax-field-kit`)
3. `claude` 실행 → 브라우저로 로그인
   - `claude` 를 못 찾으면: `& "$env:USERPROFILE\.local\bin\claude.exe"` (설치 창이 닫혔다면 2번 설치 줄을 다시 실행)
   - 고객의 로그인 계정이 관리자가 아니면: 그 계정에서 일반 PowerShell 로 2·3번(Claude 설치·로그인)을 먼저 하고, 관리자 승인 창(UAC)에서 관리자 계정으로 PowerShell 을 열어 4번을 진행한다.
4. 이 폴더(`C:\ax-field-kit`)의 `claude` 에 입력:
   > CLAUDE.md 대로 이 PC 준비해줘

이후 Tailscale 인증 키 입력과 UAC 승인만 사람이 한다(Claude 가 안내). 결과는 `C:\AxFieldKit\data\setup-report.md`.

---

# 참고 (Claude 와 사람이 함께 보는 상세)

## 설치 전 5초 문법 검사 (저장소 폴더의 PowerShell 에서)

```powershell
Get-ChildItem *.ps1 | ForEach-Object { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$e); "{0}: 오류 {1}개 {2}" -f $_.Name, $e.Count, (($e | ForEach-Object { "L$($_.Extent.StartLineNumber) $($_.Message)" }) -join ' / ') }
```
5개 파일 모두 "오류 0개"면 설치를 진행한다. 오류가 나오면 행 번호를 만든 쪽에 넘긴다.

## 수동 설치 (Claude 없이 전부 직접)

**USB zip.** 맥에서 `./make-zip.sh` 로 `ax-field-kit.zip` 생성 → USB 로 복사 → 고객 PC 에서:

```powershell
# D: 는 USB 드라이브 문자에 맞게 바꾸기
Expand-Archive D:\ax-field-kit.zip C:\ -Force; cd C:\ax-field-kit
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Customer <이름> -TsTag tag:ax-field -SshPublicKey "<공개키 한 줄>"
```
(`customers\<이름>\` 이 없으면 `-Customer` 를 빼면 기본값. 만들려면 `customers\_example` 복사.)

**대안: GitHub 공개 저장소 (Git 이 설치돼 있을 때).** 로그인·토큰 없이 받는다.

```powershell
git clone https://github.com/intellieffect/ax-field-kit-public C:\ax-field-kit
```

중간에 `Tailscale 인증 키`를 물으면 붙여넣는다(화면에 안 보임, 파일·로그·인자에 남지 않음). 붙여넣은 뒤 `Win+V` 클립보드 기록에서 해당 항목을 지운다.
Claude 다운로드·OpenSSH 설치는 진행 표시가 없어 몇 분 멈춘 것처럼 보일 수 있다. 기다리면 된다.
끝나면 `[OK]/[실패]` 요약표가 나온다. 다시 실행해도 안전하다(이미 설치된 것은 건너뜀).
인증 키는 일회용·1일 만료·ephemeral 끔·태그 권장. Claude Code 는 관리자 불필요라 **로그인한 고객 계정**으로 설치돼야 한다(다른 관리자 계정이면 경고가 뜸).

### 설치 직후 할 일
1. **트레이 아이콘 고정**: Windows 11 은 아이콘이 숨김(^) 칸으로 들어간다. 끌어내 작업 표시줄에 늘 보이게 한다("몰래 돌지 않음").
2. **첫 5분 뒤 `C:\AxFieldKit\data\recordings\` 의 mkv 1개를 열어** 전체 화면이 찍혔는지 확인한다(고배율 DPI·모니터 2대면 일부만/작게 찍힐 수 있음).
3. `check.ps1` 실행.

## 매개변수 (install.ps1)

| 매개변수 | 설명 |
|---|---|
| `-Customer <이름>` | `customers\<이름>\config.json` 사용 (없으면 `customers\_example` 기본값) |
| `-TsTag tag:xxx` | Tailscale 태그 (인증 키에 태그 권한 필요) |
| `-TsHostname <이름>` | Tailscale 기기 이름 (기본: 컴퓨터 이름) |
| `-InstallDir` | 설치 위치 (기본 `C:\AxFieldKit`) |
| `-SkipGit` `-SkipClaude` `-SkipTailscale` `-SkipRecorder` | 해당 단계 건너뜀 |
| `-SshPublicKey "ssh-ed25519 ..."` | 우리 쪽 SSH 공개키 등록 (OpenSSH 서버는 기본 설치, Tailscale 대역 100.64.0.0/10 에서만 허용) |
| `-SkipSsh` | OpenSSH 서버 설치 건너뜀 |
| `-ContinueOnError` | 단계 실패 시 묻지 않고 계속 |

철수(`uninstall.ps1`)는 sshd 중지·우리 공개키 제거가 기본이고 `-KeepSsh` 일 때만 남긴다.

설치 후 Claude Code 로그인은 해당 PC 에서 `claude` 를 실행해 진행한다.

## 녹화 동작 (구성: ffmpeg gdigrab + 작업 스케줄러 + 트레이 아이콘 1개 스크립트)

- 로그인 시 자동 시작. 트레이에 점 아이콘: **빨강=녹화 중, 회색=대기**. 우클릭으로 일시정지·폴더 열기·종료. 녹화 시작 시 알림 표시.
- 업무 시간(기본 월~금 09:00~18:00)에만 녹화. 화면 잠금·5분 무입력이면 멈춤. 디스크 여유 5GB 미만이면 멈춤.
- 초당 1장, 폭 최대 1600px, 5분 단위 `.mkv`. 활성 앱/창 제목은 `data\activity\날짜.jsonl` 에 한 줄씩(`ts, app, title`).
- 설정(`customers\<이름>\config.json`): `workStart workEnd workDays fps maxWidth crf segmentSeconds retentionDays idleSeconds minFreeGB`.
- **데이터 처리**: `C:\AxFieldKit\data` 에만 저장, `retentionDays`(기본 14일) 지나면 자동 삭제, 열람은 우리 담당자(Tailscale)만.

## 데이터 가져가기 (Tailscale 경유)

```bash
# OpenSSH 서버는 기본 설치됨(-SkipSsh 로 생략). 우리 공개키는 administrators_authorized_keys 라서
# 가져갈 때 쓰는 계정은 고객 PC 의 "관리자" 계정이어야 한다. 맥 scp 는 SFTP 모드라 /C:/ 형식이 안전하다.
scp -r 관리자계정@<tailscale-ip>:/C:/AxFieldKit/data/activity ./pull/
scp -r 관리자계정@<tailscale-ip>:/C:/AxFieldKit/data/recordings ./pull/    # Windows 에는 rsync 가 없다
```
`-SkipSsh` 를 쓴 경우: 관리자 계정으로 `\\<tailscale-ip>\C$\AxFieldKit\data` (SMB) 접근.

## 확인 / 끄기 / 지우기

- 확인: `powershell -ExecutionPolicy Bypass -File .\check.ps1`
- 일시 중지: 트레이 아이콘 → 일시정지
- 철수(녹화 중지·자동시작 제거·Tailscale 로그아웃, 녹화 파일은 묻고 처리): `powershell -ExecutionPolicy Bypass -File .\uninstall.ps1`

## 막혔을 때

| 증상 | 대안 |
|---|---|
| 관리자 권한 없음 | 고객사 IT 에 관리자 계정 요청. 불가하면 `-SkipGit -SkipTailscale -SkipSsh -SkipRecorder` 로 Claude Code 만(사용자 권한) 설치. 사전 점검이 "계속할까요?" 로 물으면 `y` |
| 스크립트 실행 정책 | 항상 `powershell -ExecutionPolicy Bypass -File ...` 로 실행 |
| GitHub 차단/인증 불가 | 기본 경로(USB zip) 사용 |
| 실행 정책이 GPO | `Get-ExecutionPolicy -List` 의 MachinePolicy 가 설정돼 있으면 Bypass 가 무시된다 → 고객사 IT 에 문의 |
| 백신/EDR 이 막음 | recorder.ps1·ffmpeg.exe 를 차단하면 `C:\AxFieldKit` 예외 등록을 IT 에 요청 |
| winget 없음 | Microsoft Store "앱 설치 관리자" 업데이트, 또는 Git/Tailscale/ffmpeg 수동 설치 후 재실행(ffmpeg.exe 는 `C:\AxFieldKit\bin\` 에) |
| 인증 키 오류 | 키 만료·재사용 불가·태그 권한 확인, 새 키로 재실행 |
| 녹화 안 됨 | `data\recorder.log`, `data\ffmpeg-error.log` 확인 / 업무 시간·잠금·무입력 상태인지 확인 |

> 이 키트는 Windows 실기 검증 전 첫 현장 실행 판이다. 정교한 판은 이후 교체.
