# ax-field-kit

고객사 Windows PC 현장 설치 키트. **담당자는 Claude Code 설치와 로그인까지만 직접 하고, 나머지는 이 폴더를 연 Claude Code 가 `CLAUDE.md` 대로 준비한다.**

## 설치 전: SSH·Tailscale 통로부터

키트는 공개 저장소 `intellieffect/ax-field-kit-public`에서 로그인 없이 받습니다(USB·GitHub 로그인 불필요). 고객명·상호·위치·연락처·실제 업무 자료는 저장소에 넣지 않습니다.

1. 고객 PC가 Windows 10/11인지, 관리자 권한·보안 프로그램·인터넷·여유 공간을 확인합니다. 권한/보안 거부는 즉시 중단합니다. 녹화 대상 직원 모두의 **서면 동의서**(키트 밖 별도 양식)를 받았는지 확인합니다. 받기 전에는 녹화를 설치하지 않습니다(`-SkipRecorder`로 통로만).
2. 맥북에서 `tailscale status --json`의 `CurrentTailnet.Name`을 확인하고 **같은 테일넷**에서 Settings → Keys로 일회용·1일 만료·ephemeral 끔·`tag:ax-field` 키를 발급합니다. 인증 키와 정책 접근 키는 비밀 보관소에 둡니다. 값은 문서·인자·보고서에 적지 않습니다.
3. 맥북 → `tag:ax-field` tcp:22 정책 초안을 미리 준비합니다. **담당자 확인 전 정책 적용 금지.** 태그 소유 권한도 확인합니다.
4. 아래 Claude 설치·로그인 후, Claude가 **사람이 전용 계정 생성 → OpenSSH → Tailscale 설치 → 사람이 가입 → 맥북 SSH 확인**까지 먼저 진행합니다. 녹화 설치는 통로 확인 뒤입니다.
5. 연결 판단은 맥북의 `nc -vz <ip> 22` / 일반 `ping`으로 합니다. `tailscale ping` 성공만으로 SSH가 된다고 판단하지 않습니다. 이 명령은 현장에서 승인된 고객 PC에만 실행합니다.
6. 태그 기기는 Taildrop 사용 가능 여부를 별도로 확인합니다. Taildrop은 필수 조건이 아니며 SSH/SFTP를 기본 통로로 씁니다. 받은 Taildrop 파일은 **다운로드 폴더**에서 찾습니다.
7. SSH 계정은 **원격 통로 전용 일반 계정**(Users 그룹만)입니다. 사람이 `new-access-account.ps1`로 만들고(암호는 사람이 화면에서 입력), 우리 공개키는 그 계정의 `.ssh\authorized_keys`에 주석 `ops-<고객>-<기기>-<날짜>`로 들어갑니다. 맥북 SSH 별칭 `User`에는 전용 계정 이름을 적습니다. 회수는 계정·프로필 삭제로 끝납니다. 경로는 `$env:USERPROFILE`·`Join-Path`로 처리하고 수동 명령의 경로는 따옴표로 감쌉니다. 녹화 예약 작업은 로그인한 고객 계정의 `DOMAIN\사용자`(Interactive/Limited)로 등록합니다. 관리자와 로그인 계정이 다르면 각각 구분해 확인합니다.

## 담당자가 직접 칠 것 (관리자 PowerShell)

1. 키트 받기 (인터넷만 있으면 된다):
   ```powershell
   cd $env:TEMP; iwr https://github.com/intellieffect/ax-field-kit-public/archive/refs/heads/main.zip -OutFile axk.zip -UseBasicParsing
   Expand-Archive axk.zip axk -Force; Move-Item axk\ax-field-kit-public-main C:\ax-field-kit; Get-ChildItem C:\ax-field-kit -Recurse | Unblock-File; cd C:\ax-field-kit
   ```
   (`C:\ax-field-kit`가 이미 있으면 Move-Item 이 멈춘다. 옛 폴더 이름을 바꾼 뒤 다시 실행)
2. Claude Code 공식 설치:
   ```powershell
   irm https://claude.ai/install.ps1 | iex
   ```
   (끝나면 PowerShell 을 닫고 **관리자 PowerShell 을 새로 열어** `cd C:\ax-field-kit`)
3. `claude` 실행 → 브라우저로 로그인. 처음에는 **우리 계정**으로 한다. 나중에 고객 계정으로 바꾸거나 철수할 때 `claude` 에서 `/logout` 으로 우리 계정을 뺀다.
   - `claude` 를 못 찾으면: `& "$env:USERPROFILE\.local\bin\claude.exe"` (설치 창이 닫혔다면 2번 설치 줄을 다시 실행)
   - 고객의 로그인 계정이 관리자가 아니면: 그 계정에서 일반 PowerShell 로 2·3번(Claude 설치·로그인)을 먼저 하고, 관리자 승인 창(UAC)에서 관리자 계정으로 PowerShell 을 열어 4번을 진행한다.
4. 이 폴더(`C:\ax-field-kit`)의 `claude` 에 입력:
   > CLAUDE.md 대로 이 PC 준비해줘

이후 전용 계정 만들기(암호 입력)·Tailscale 인증 키 입력과 UAC 승인만 사람이 한다(Claude 가 안내). 결과는 `C:\AxFieldKit\data\setup-report.md`.

---

# 참고 (Claude 와 사람이 함께 보는 상세)

## 설치 전 5초 문법 검사 (저장소 폴더의 PowerShell 에서)

```powershell
Get-ChildItem *.ps1 | ForEach-Object { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$e); "{0}: 오류 {1}개 {2}" -f $_.Name, $e.Count, (($e | ForEach-Object { "L$($_.Extent.StartLineNumber) $($_.Message)" }) -join ' / ') }
```
7개 파일 모두 "오류 0개"면 설치를 진행한다. 오류가 나오면 행 번호를 만든 쪽에 넘긴다.

## 수동 설치 (Claude 없이 전부 직접)

위 「키트 받기」로 `C:\ax-field-kit`을 만든 뒤:

```powershell
cd C:\ax-field-kit
# 원격 통로 전용 일반 계정 (암호는 사람이 직접 입력)
powershell -ExecutionPolicy Bypass -File .\new-access-account.ps1 -UserName <전용계정>
# 먼저 통로만 설치 (키 입력은 사람이 직접)
powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipGit -SkipClaude -SkipRecorder -TsTag tag:ax-field -TsHostname <고객>-<기기> -ExpectedTailnet "<맥북 CurrentTailnet.Name>" -SshUser <전용계정> -SshPublicKey "<공개키 한 줄>" -SshKeyComment ops-<고객>-<기기>-<날짜>
# 맥북에서 nc 및 SSH 공개키 로그인 확인 뒤, 민감 화면을 닫고 녹화 설치
powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipClaude -SkipTailscale -SkipSsh
```
(녹화 설정은 기본값 `customers\_example`을 쓴다. 바꿀 값이 있으면 `customers\_example`을 `customers\<고객>`으로 복사해 고치고 `-Customer <고객>`을 붙인다. 지정한 config 가 없으면 오류.)

중간에 `Tailscale 인증 키`를 물으면 붙여넣는다(화면에 안 보임, 로그·인자에 값이 남지 않음; ACL을 제한한 임시 파일로 전달 후 즉시 삭제). 붙여넣은 뒤 `Win+V` 클립보드 기록에서 해당 항목을 지운다.
Claude 다운로드·OpenSSH 설치는 진행 표시가 없어 몇 분 멈춘 것처럼 보일 수 있다. 기다리면 된다.
끝나면 `[OK]/[실패]` 요약표가 나온다. 이미 설치된 프로그램은 건너뛰지만 서비스·방화벽·예약 작업 설정은 다시 적용됩니다. 실패 후 원인을 확인하기 전 재실행하지 않습니다.
인증 키는 일회용·1일 만료·ephemeral 끔·태그 권장. Claude Code 는 관리자 불필요라 **로그인한 고객 계정**으로 설치돼야 한다(다른 관리자 계정이면 경고가 뜸).

### 설치 직후 할 일
1. **트레이는 기본 숨김**이라 작업 표시줄에 아무것도 보이지 않는 것이 정상이다(`showTray`).
2. **첫 5분 뒤 `C:\AxFieldKit\data\recordings\` 의 mkv 1개를 열어** 전체 화면이 찍혔는지 확인한다(고배율 DPI·모니터 2대면 일부만/작게 찍힐 수 있음).
3. `check.ps1 -ExpectedTailnet "<맥북 CurrentTailnet.Name>" -SshUser <전용계정>` 실행.

## 매개변수 (install.ps1)

| 매개변수 | 설명 |
|---|---|
| `-Customer <이름>` | `customers\<이름>\config.json` 사용 (지정한 파일 없으면 중단, 매개변수 생략 시 `_example` 기본값) |
| `-TsTag tag:xxx` | Tailscale 태그 (인증 키에 태그 권한 필요) |
| `-ExpectedTailnet <이름>` | 맥북 `CurrentTailnet.Name`과 같은 값. 가입/check 시 필수이며 미지정·불일치·확인 불가면 실패 |
| `-TsHostname <이름>` | Tailscale 기기 이름 (기본: 컴퓨터 이름) |
| `-InstallDir` | 설치 위치 (기본 `C:\AxFieldKit`) |
| `-SkipGit` `-SkipClaude` `-SkipTailscale` `-SkipRecorder` | 해당 단계 건너뜀 |
| `-SshPublicKey "ssh-ed25519 ..."` | 우리 쪽 SSH 공개키를 전용 계정의 `.ssh\authorized_keys`에 등록 (OpenSSH 서버는 기본 설치, Tailscale 대역 100.64.0.0/10 에서만 허용). 관리자 키 파일에는 넣지 않음 |
| `-SshUser <전용계정>` | 원격 통로 전용 일반 계정. `-SshPublicKey`와 함께 필수. 사람이 `new-access-account.ps1`로 먼저 만들어야 하며, 없거나 Administrators 소속이면 실패. 이 계정만 SSH 비밀번호 로그인을 끈다(`sshd_config` 끝 표식 블록, 키 로그인만. 블록·검증 함수는 install·check·uninstall 이 같이 쓰는 `sshd-keyonly.ps1`, 키트 폴더째 두고 실행). 암호 만료는 Windows 기본값(42일) — 만료 뒤에도 키 로그인 됨, 화면 로그인 때 새 암호 |
| `-SshKeyComment ops-<고객>-<기기>-<날짜>` | 키 줄 끝 주석(영문·숫자·`-`, 날짜 8자리). 생략하면 공개키 줄의 주석을 쓰고, 형식이 다르면 실패 |
| `-SkipSsh` | OpenSSH 서버 설치 건너뜀 |
| `-ContinueOnError` | 호환용 구 옵션. 현재는 어떤 단계 실패든 중단 |

철수(`uninstall.ps1 -SshUser <전용계정>`)는 전용 계정 키 → 관리자 키(옛 판 `ax-field-kit` 줄) → 전용 계정·프로필 순서로 회수한다. 우리 공개키는 항상 지우고, 계정·프로필 삭제는 사람에게 묻는다(`-KeepSshUser`면 묻지 않고 남김, `new-access-account.ps1`이 만든 계정만 대상). `sshd_config`의 우리 표식 블록(전용 계정 비밀번호 SSH 끄기)은 `-KeepSsh`여도 지운다. 지우는 것은 `-SshUser` 계정의 블록뿐이라, 전용 계정이 둘 이상이면 남는 계정의 블록은 그대로다. sshd 중지·방화벽 규칙 제거가 기본이고 `-KeepSsh`면 서비스·방화벽은 그대로 두고 사전 기록대로 사람이 복구한다. 전용 계정 프로필이 아직 로드돼 있다며 계정 삭제가 멈추면(접속을 끊어도 재부팅 전까지 남을 수 있음) PC를 다시 시작한 뒤 uninstall 을 `-SshUser` 로 다시 실행한다(키·방화벽 회수는 이미 끝남).

설치 후 Claude Code 로그인은 해당 PC 에서 `claude` 를 실행해 진행한다.

## 녹화 동작 (구성: ffmpeg gdigrab + 작업 스케줄러 + 트레이 아이콘 1개 스크립트)

- 로그인 시 자동 시작. 트레이 아이콘·알림은 **기본 숨김**(`showTray: false`). `true`로 두면 점 아이콘(빨강=녹화 중, 회색=대기), 우클릭 일시정지·폴더 열기·종료, 녹화 시작 알림이 보인다.
- 화면이 켜진 업무 시간(기본 월~금 09:00~18:00)에만 녹화. Windows가 화면 꺼짐을 알리면 다음 제어 주기(약 2초)에 멈추고, 다시 켜지면 기존 업무 시간·잠금·무입력·여유 공간 조건을 확인한 뒤 재개한다. 화면 상태 미확인·알림 등록 실패 시에도 녹화하지 않는다. 화면이 어두워진 상태(dim)는 켜짐으로 취급한다.
- 화면 잠금·5분 무입력·디스크 여유 5GB 미만이면 기존대로 멈춘다. 화면 꺼짐 대기 중에는 앱·창 이름 기록도 하지 않는다. 이 기능은 전원 계획·SSH·Tailscale 설정을 바꾸지 않는다.
- 화면 상태는 로그인 세션의 Windows 전원 알림(`GUID_SESSION_DISPLAY_STATUS`) 기준이다. 개별 모니터의 물리 전원 버튼·케이블 분리나 다중 모니터 조합이 같은 알림을 보내는지는 기기별 확인이 필요하다. 잠금 해제나 화면 켜짐을 강제로 발생시키지는 않는다.
- 초당 1장, 폭 최대 1600px, 5분 단위 `.mkv`. 활성 앱/창 제목은 `data\activity\날짜.jsonl` 에 한 줄씩(`ts, app, title`).
- 설정(`customers\<이름>\config.json`): `workStart workEnd workDays fps maxWidth crf segmentSeconds retentionDays idleSeconds minFreeGB showTray`.
- **데이터 처리**: 고객 PC는 `C:\AxFieldKit\data` 에만 저장, `retentionDays`(기본 14일) 지나면 자동 삭제. 가져온 녹화·활동 기록은 **지정 보관 장치** 에만 둔다(맥북 등 다른 곳에 남기지 않음).

## 데이터 가져가기 (Tailscale 경유, 지정 보관 위치·범위 승인 후에만)

```bash
# OpenSSH 서버는 기본 설치됨(-SkipSsh 로 생략). 우리 공개키는 전용 일반 계정의 authorized_keys 라서
# 가져갈 때 쓰는 계정은 그 전용 계정이다(install-recorder.ps1 이 data 에 Users 권한을 준다). 맥 scp 는 SFTP 모드라 /C:/ 형식이 안전하다.
scp -r 전용계정@<tailscale-ip>:/C:/AxFieldKit/data/activity ./pull/
scp -r 전용계정@<tailscale-ip>:/C:/AxFieldKit/data/recordings ./pull/    # Windows 에는 rsync 가 없다
```
`-SkipSsh` 를 쓴 경우: 관리자 계정으로 `\\<tailscale-ip>\C$\AxFieldKit\data` (SMB) 접근.

## 민감 화면·동의

녹화·활동 기록은 고객 PC `C:\AxFieldKit\data`에 평일 09~18시 것만 남고 14일 뒤 지워집니다. 자동 삭제는 recorder가 실행 중일 때 10분 간격으로 영상/활동 파일의 수정 시각을 검사하며, 종료 중에는 삭제되지 않습니다. 운영 로그는 이 자동 삭제 대상이 아닙니다.

트레이가 기본 숨김이라 직원이 녹화를 멈출 수 없고, 창 제목·프로세스 기준 녹화 제외도 **미지원**입니다. 홈택스·공동인증서·거래처 개인정보 화면도 그대로 녹화됩니다. 그래서 녹화 대상 직원 모두에게 **서면 동의서**를 받은 뒤에만 녹화를 설치합니다. 일시정지가 꼭 필요한 PC는 고객 설정에 `"showTray": true`를 넣어 설치하고, 민감 화면을 열기 전에 트레이 → 일시정지(약 2초 뒤 회색 `paused`와 ffmpeg 정지 확인)를 씁니다.

## 확인 / 끄기 / 지우기

- 확인: `powershell -ExecutionPolicy Bypass -File .\check.ps1 -ExpectedTailnet "<맥북 CurrentTailnet.Name>" -SshUser <전용계정>`
- 일시 중지: `showTray: true`로 설치한 PC만 트레이 아이콘 → 일시정지
- 철수(녹화 중지·자동시작 제거·우리 키 제거·Tailscale 로그아웃, 녹화 파일·전용 계정은 묻고 처리): `powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -SshUser <전용계정>`

## 막혔을 때

| 증상 | 대안 |
|---|---|
| 관리자 권한 없음 | 고객사 IT 에 관리자 계정 요청. 불가하면 일반 PowerShell에서 공식 Claude 설치·로그인까지만 하고 중단. install.ps1은 관리자 권한 없으면 중단 |
| 스크립트 실행 정책 | 항상 `powershell -ExecutionPolicy Bypass -File ...` 로 실행 |
| github.com 차단 | 고객사 IT 에 github.com 허용 요청. 안 되면 그날은 중단 |
| 실행 정책이 GPO | `Get-ExecutionPolicy -List` 의 MachinePolicy 가 설정돼 있으면 Bypass 가 무시된다 → 고객사 IT 에 문의 |
| 백신/EDR 이 막음 | recorder.ps1·ffmpeg.exe 를 차단하면 `C:\AxFieldKit` 예외 등록을 IT 에 요청 |
| winget 없음 | Microsoft Store "앱 설치 관리자" 업데이트, 또는 Git/Tailscale/ffmpeg 수동 설치 후 재실행(ffmpeg.exe 는 `C:\AxFieldKit\bin\` 에) |
| 인증 키 오류 | 키 만료·재사용 불가·태그 권한 확인, 새 키로 재실행 |
| 녹화 안 됨 | `data\recorder.log`, `data\ffmpeg-error.log` 확인 / 업무 시간·잠금·무입력 상태인지 확인 |

> 이 키트는 Windows 실기 검증 전 첫 현장 실행 판이다. 정교한 판은 이후 교체.

## 현장 기록·철수 경계

고객 PC 접속은 지정 관제와 그 워커 하나로 모읍니다. 평일 업무 중 재부팅·업데이트·로그아웃·네트워크 단절과 무단 창/알림/소리 발생을 피하고, 설치 시간은 담당자가 현장에서 조율합니다. 트레이·알림은 기본 숨김이며 서면 동의를 받은 PC에만 녹화를 설치합니다. 키트 밖 프로그램·계정·권한 변경, 고객 연락, 업무 시스템 쓰기·발송·결제·제출은 진행하지 않습니다.

기존 설정이 있으면 변경 전 스크립트·config·authorized_keys·예약 작업 XML을 날짜 붙인 백업으로 보존하고 sshd 시작형식/상태와 관련 방화벽 규칙을 기록합니다. 백업 실패 시 중단합니다. 새 설치도 시각·변경·명령·복구법을 고객 PC의 setup-report.md에 적고, 지정 관제에는 고객 자료 없이 변경 요지만 전달합니다. PC 이상은 즉시 중단하고 자기 변경을 백업으로 복구한 뒤 관제에 보고합니다.

철수는 담당자 판단으로 녹화 정지·예약 작업 제거·우리 키 제거·Tailscale 로그아웃·우리 Claude 계정 `/logout`, 승인된 정책 줄 제거를 따로 확인합니다. 데이터는 보존/삭제를 사람이 결정합니다. 기존 SSH가 있으면 `-KeepSsh`로 유지하고 우리 키만 따로 회수하며, 기존 방화벽·서비스 상태는 사전 기록으로 복구합니다. gui-run을 별도 설치했다면 그 파일/예약 작업도 변경 기록에 따라 회수합니다(키트에는 gui-run 없음).
