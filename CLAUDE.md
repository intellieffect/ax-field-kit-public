# CLAUDE.md — 고객 PC 준비 지시서

이 폴더(`C:\ax-field-kit`)에서 사용자가 "CLAUDE.md 대로 이 PC 준비해줘"라고 하면 아래 순서로 진행합니다. 설치·녹화 범위와 시각은 담당자가 현장에서 확인합니다. 결과는 `C:\AxFieldKit\data\setup-report.md`에 저장합니다.

## 지켜야 할 선

- 모든 명령은 PowerShell 도구로 실행합니다. 관리자 권한 없으면 설치를 멈추고 사람이 관리자 PowerShell을 열도록 안내합니다.
- Tailscale 인증 키는 사람이 직접 입력합니다. 키를 묻거나 받아서 명령 인자·환경 변수·보고서에 적지 않습니다. 사람이 실행하는 가입 스크립트는 빈 임시 파일에 ACL을 적용하고 키를 쓴 뒤 finally에서 삭제합니다.
- 권한·인증·보안 거부는 첫 실패에서 중단합니다. GPO·백신/EDR·Defender를 끄거나 임의 예외 등록하지 않습니다. 같은 일반 실패가 두 번이면 중단합니다.
- 접속은 지정 관제와 그 워커 하나만 합니다. 고객 업무 중 재부팅·업데이트·로그아웃·네트워크 단절은 하지 않습니다. 설치 시각은 사람이 조율합니다. 트레이·알림은 기본 숨김입니다(서면 동의 전제).
- 고객 파일/설정은 키트와 `C:\AxFieldKit` 밖에서 열람·변경하지 않습니다. 예외는 키트 설치가 관리하는 프로그램·예약 작업·OpenSSH·관련 방화벽/키 파일과 사람이 만든 원격 통로 전용 계정입니다. 다른 프로그램·계정·권한 변경은 하지 않습니다.
- 업무 시스템 쓰기·발송·결제·제출과 고객 연락은 하지 않습니다. 고객 데이터는 고객 PC에 둡니다. 외부 전달은 승인된 요지와 화면 범위만이며 공개 저장소에 고객명·개인정보를 넣지 않습니다.
- 스크립트 임의 수정 금지. PC 이상 시 즉시 중단하고 자기 변경만 백업으로 복구, 지정 관제에 보고합니다.

## 순서

1. **문법 검사.** 7개 모두 오류 0개여야 진행합니다. 오류가 있으면 파일·행을 적고 중단합니다.
   ```powershell
   Get-ChildItem *.ps1 | ForEach-Object { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$e); "{0}: 오류 {1}개 {2}" -f $_.Name, $e.Count, (($e | ForEach-Object { "L$($_.Extent.StartLineNumber) $($_.Message)" }) -join ' / ') }
   ```
2. **사전 확인·복구 준비.** Windows 10/11, 관리자 권한, 인터넷, 디스크 5GB 이상, 로그인 고객 계정과 관리자 계정을 구분합니다. 한글 이름은 그대로 유지하고 `$env:USERPROFILE`·`Join-Path`·따옴표를 사용합니다. 녹화 예약 작업은 로그인 고객의 `DOMAIN\사용자`로 등록합니다. 기존 스크립트/config/관리자·전용 계정 authorized_keys/작업 XML이 있으면 `*.bak-<날짜>`로 보존하고, sshd 상태·시작형식·관련 방화벽 규칙을 기록합니다. 백업 실패 시 중단합니다. SSH는 **전용 일반 계정**(Users 그룹만, 관리자 아님)이며 키 파일은 그 계정의 `.ssh\authorized_keys`입니다. 키 주석은 `ops-<고객>-<기기>-<날짜>`(영문·숫자·`-`만)입니다. 전용 계정 이름·공개키 본문·키 주석·Tailscale 기기 이름(`<고객>-<기기>`)을 사람이 지정합니다. 녹화 설정은 기본값(`customers\_example`)을 씁니다. 사람이 바꿀 값을 말하면 `customers\_example`을 `customers\<고객>`으로 복사해 그 값만 고치고 `-Customer <고객>`을 붙입니다. 공개키 없이 비밀번호 통로로 바꾸지 않습니다.
3. **전용 계정은 사람이 직접 → OpenSSH 통로 설치(녹화·앱·가입 제외).**
   먼저 사람이 새 관리자 PowerShell에서 전용 계정을 만들도록 안내합니다(순서 4의 Tailscale 키 입력과 같은 방식). 암호는 사람이 화면에서 입력하고, Claude는 이 스크립트를 대신 실행하지 않으며 암호를 묻거나 받지 않습니다. 고객 본인 계정·잠금 정책·`LimitBlankPasswordUse`는 건드리지 않습니다.
   ```powershell
   cd C:\ax-field-kit
   powershell -NoProfile -ExecutionPolicy Bypass -File .\new-access-account.ps1 -UserName <전용계정>
   ```
   사람이 완료했다고 하면 출력의 `Users=True Administrators=False`를 확인한 뒤 SSH 단계를 실행합니다. 계정이 없거나 Administrators 소속이면 install이 실패로 멈춥니다(그룹 변경은 사람이 결정).
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -SkipGit -SkipClaude -SkipTailscale -SkipRecorder -SshUser <전용계정> -SshPublicKey "<맥북 공개키>" -SshKeyComment ops-<고객>-<기기>-<날짜>
   ```
   결과가 실패면 중단합니다. `-ContinueOnError`를 사용하지 않습니다. 관리자 키 파일(`administrators_authorized_keys`)에는 등록하지 않습니다.
4. **Tailscale 설치·가입은 사람이 직접.** 맥북 `CurrentTailnet.Name`을 사람에게 확인해 아래 `<맥북 CurrentTailnet.Name>`을 실제 기대 이름으로 바꿉니다. 미지정·다른 테일넷·이름 확인 불가면 install/check가 실패합니다. README의 인증 키 발급·태그·정책 승인 준비를 확인하고 사람이 새 관리자 PowerShell에서 다음 명령을 직접 실행하도록 안내합니다. Claude가 대신 실행하지 않습니다.
   ```powershell
   cd C:\ax-field-kit
   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -SkipGit -SkipClaude -SkipRecorder -SkipSsh -TsTag tag:ax-field -TsHostname <고객>-<기기> -ExpectedTailnet "<맥북 CurrentTailnet.Name>"
   ```
   사람이 완료했다고 해도 `tailscale status --json`의 가입 테일넷·태그와 `tailscale ip -4`를 확인합니다. 기존에 다른 테일넷으로 가입돼 있으면 로그아웃/재가입을 자동 실행하지 말고 중단합니다.
5. **맥북에서 통로 확인(사람/지정 관제 몫).** 승인된 정책에서 `nc -vz <ip> 22`와 **전용 계정**으로 SSH 공개키 로그인을 확인합니다. SSH 별칭 `User`에는 전용 계정 이름을 적습니다. `tailscale ping`만으로 성공 판정하지 않습니다. Taildrop은 태그 기기에서 미지원일 수 있으므로 SSH/SFTP를 기본으로 하고, Taildrop 수신 파일은 다운로드 폴더에서 찾습니다. 통로 확인 전 녹화 설치 금지.
6. **통로 확인 뒤 Git·녹화 설치.** 녹화 대상 직원의 **서면 동의서를 받았다고 사람이 확인**하고 녹화 설치를 진행하라고 한 경우만 실행합니다. 동의서 사본·내용은 보고서에 적지 않습니다. 확인이 없으면 녹화를 보류합니다.
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -SkipClaude -SkipTailscale -SkipSsh
   ```
   트레이·알림은 기본 숨김이라 직원이 일시정지할 수 없고, 창/프로세스 자동 제외도 미지원이라 민감 화면도 녹화됩니다. 사람이 일시정지가 필요하다고 하면 `customers\_example`을 `customers\<고객>`으로 복사해 `"showTray": true`로 고치고 `-Customer <고객>`으로 설치합니다.
7. **확인.** 관리자 PowerShell에서 `powershell -NoProfile -ExecutionPolicy Bypass -File .\check.ps1 -ExpectedTailnet "<맥북 CurrentTailnet.Name>" -SshUser <전용계정>` 실행(전용 계정 존재·그룹·잠김·우리 키 줄 수 포함). 업무시간 중 5분 뒤 mkv 존재·0보다 큰 크기, 활동 파일 존재만 확인하고 실제 화면 검수는 사람이 민감정보 없는 영상 하나로 합니다. 모니터 2대/배율도 확인합니다. 업무시간 밖은 대기 정상으로 쓰고 다음 업무시간 검증을 남깁니다.
8. **결과 표·변경 기록.** 아래 표와 날짜·Windows 버전·남은 일, 전용 계정 이름·키 주석, 각 변경의 시각·명령(비밀 제외)·백업 경로·되돌리는 법을 보고서에 저장합니다. 전용 계정 암호는 어디에도 적지 않습니다. 고객 업무 화면·창 제목·원문 자료를 보고서에 복사하지 않습니다. 보관은 고객 PC 내부, 평일 09~18시, 기본 14일입니다. 자동 삭제는 recorder 실행 중에만 영상/활동 파일에 적용되며 운영 로그는 별도입니다.

| 단계 | 결과 | 비고 |
|---|---|---|
| 문법 검사 | ✅/❌ | 7개 파일 오류 수 |
| 전용 계정 | ✅/❌/⏳ | 사람 입력. 이름·Users만·잠김 아님 (암호 기록 안 함) |
| OpenSSH | ✅/❌ | 전용 계정 공개키(주석)·서비스·방화벽 |
| Tailscale | ✅/❌/⏳ | 같은 테일넷·태그·IP, 사람 입력 |
| 맥북 통로 | ✅/❌/⏳ | nc tcp:22 및 공개키 로그인 확인 |
| Git / Claude Code | ✅/❌ | 버전, Claude는 사람이 설치 |
| 녹화 설치 | ✅/❌/⏳ | 예약 작업의 로그인 사용자·프로세스 |
| 서면 동의서 | ✅/⏳ | 사람 확인 (사본·내용은 적지 않음) |
| 첫 녹화 | ✅/❌/⏳ | 파일 크기·전체 화면은 사람 검수 |

## 철수

담당자 요청 시만 `uninstall.ps1 -SshUser <전용계정>`을 실행하며 데이터 삭제와 전용 계정 삭제는 사람이 결정합니다(스크립트가 묻는 질문에 사람이 답합니다. Claude가 실행할 때는 `-KeepData -KeepSshUser`로 묻지 않고 보존한 뒤 삭제는 사람에게 넘깁니다). 회수 순서는 전용 계정 키 → 관리자 키(옛 판 `ax-field-kit` 표식 줄) → 전용 계정·프로필입니다. 기존 SSH가 있으면 `-KeepSsh`로 서비스·방화벽을 유지하고(우리 키는 항상 지움) 사전 방화벽/서비스 상태로 사람이 복구합니다. 승인된 Tailscale 정책 줄 삭제는 지정 관제에서 별도 확인합니다. 별도 gui-run 파일/작업이 있다면 변경 기록으로 회수합니다. 고객 PC에 남긴 백업·자료 경로를 기록합니다. 키트 밖 삭제를 임의 수행하지 않습니다. 이 PC의 Claude가 우리 계정으로 로그인돼 있으면 마지막에 사람이 `/logout` 하도록 안내합니다.

원격 통로(Tailscale·SSH) 개통·회수·막힘 절차와 개통 기록 양식은 `docs/원격-통로.md`, `docs/양식/원격통로-개통기록.md`를 봅니다.
