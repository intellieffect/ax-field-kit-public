# CLAUDE.md — 고객 PC 준비 지시서

이 폴더(`C:\ax-field-kit`)에서 Claude Code 가 열리면, 사용자가 "CLAUDE.md 대로 이 PC 준비해줘"라고 할 때 아래를 **순서대로** 실행한다.
대상은 고객사 Windows PC 이고, 고객은 업무 AX(분석)를 위한 설치에 동의했다. 동의 문구·동의 화면은 만들지 않는다.
각 단계 결과를 기록해 두었다가 마지막에 ✅/❌ 표로 출력하고 `C:\AxFieldKit\data\setup-report.md` 에 저장한다.

## 지켜야 할 선
- **모든 명령은 PowerShell 도구로 실행한다.**
- **Tailscale 인증 키는 사람이 직접 입력한다.** 키를 사용자에게 물어 받거나, 명령 인자·환경 변수·파일·로그·보고서에 쓰지 않는다. 키를 보게 되는 일 자체를 만들지 않는다.
- **UAC/관리자 승인은 사람이 한다.** 관리자 PowerShell 이 아니면 멈추고 사람에게 "관리자 PowerShell 에서 claude 를 다시 여세요"라고 안내한다.
- **보안 설정을 끄지 않는다.** 백신/EDR 예외 등록, 실행 정책 GPO 변경, 방화벽 해제, Defender 끄기 금지. 막히면 그 사실을 사람에게 알리고 고객 IT 에 요청할 문구만 제안한다.
- **녹화는 트레이 표시가 있는 방식 그대로** 둔다. 아이콘·알림을 숨기거나 끄는 변경 금지.
- **`C:\AxFieldKit` 과 이 키트 폴더 밖의 고객 파일·설정은 열람·수정하지 않는다**(녹화 확인은 `C:\AxFieldKit\data` 파일의 존재·크기만). (예외: install.ps1 이 하는 일 — 프로그램 설치, 작업 스케줄러 `AxFieldKitRecorder`, Tailscale, OpenSSH 방화벽 규칙)
- 키트 스크립트를 임의로 고치지 않는다. 고쳐야 할 것 같으면 사람에게 알린다.
- 비밀값(토큰, 키, 비밀번호)을 출력·기록하지 않는다.

## 순서

1. **문법 검사 ★** (이 폴더에서). 5개 모두 "오류 0개"여야 진행한다. 오류가 있으면 파일·행을 보고서에 적고 중단, 사람에게 알린다.
   ```powershell
   Get-ChildItem *.ps1 | ForEach-Object { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$e); "{0}: 오류 {1}개 {2}" -f $_.Name, $e.Count, (($e | ForEach-Object { "L$($_.Extent.StartLineNumber) $($_.Message)" }) -join ' / ') }
   ```
2. **사전 확인.** 관리자 권한인지(`whoami /groups` 에 S-1-16-12288 High), 사용자에게 다음을 묻는다: Tailscale 태그(기본 `tag:ax-field`), 우리 SSH **공개키** 한 줄(공개키는 비밀이 아니다. 없으면 `-SshPublicKey` 생략하고 보고서에 "비밀번호 접속"으로 적음), 고객 설정 이름(기본 `_example`). **`customers\<이름>\config.json` 이 있을 때만 `-Customer <이름>` 을 붙이고, 없으면 `-Customer` 를 빼고 실행한다**(기본값 사용).
3. **install.ps1 실행 (Claude 단계·Tailscale 가입 제외).** Claude 는 사람이 이미 설치했고, Tailscale 가입은 키 입력이 필요하므로 건너뛴다:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipClaude -SkipTailscale -ContinueOnError [-Customer <이름>] -SshPublicKey "<공개키>"
   ```
   (`[-Customer <이름>]` 은 선택: config.json 이 있을 때만. Git → OpenSSH → 녹화 설치. 단 Tailscale 를 건너뛰므로 SSH 방화벽 규칙은 Tailscale 대역 기준이라 그대로 유효.)
   실패한 단계는 README "막혔을 때" 표를 보고 대안을 **제안**한다(실행 정책·백신은 사람에게 넘김). 같은 실패가 2번이면 멈추고 사람에게 알린다.
4. **Tailscale 설치·가입 — 사람이 직접.** 먼저 Tailscale 프로그램만 설치되게 하고(`winget install --id Tailscale.Tailscale -e --silent --accept-source-agreements --accept-package-agreements`, 실패 시 install.ps1 의 MSI 경로 안내), 가입은 사람에게 이렇게 안내한다:
   > 새 **관리자 PowerShell** 창을 열어 아래를 직접 실행하세요. 인증 키를 물으면 붙여넣으세요(화면에 안 보임). 끝나면 알려 주세요.
   > `cd C:\ax-field-kit; powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipGit -SkipClaude -SkipRecorder -SkipSsh -TsTag tag:ax-field`
   Claude 는 이 명령을 **대신 실행하지 않는다**(Read-Host 가 Claude 의 셸에서 동작하지 않고, 키가 Claude 에게 보이면 안 된다). 사람이 "끝났다"고 하면 다음으로.
5. **check.ps1 실행.** `powershell -ExecutionPolicy Bypass -File .\check.ps1` 출력(Claude Code 버전, Tailscale 상태·IP, 작업 스케줄러, 녹화 프로세스)을 표에 반영한다. 키·토큰은 출력에 없지만 혹시 보이면 보고서에 옮기지 않는다.
6. **트레이 아이콘 고정 안내 (사람 몫).** "작업 표시줄 오른쪽 ^ 를 눌러 빨강/회색 점 아이콘을 작업 표시줄로 끌어내 늘 보이게 하세요." 확인되면 ✅.
7. **5분 뒤 첫 녹화 파일 확인.** 업무 시간(기본 월~금 09~18시) 안이고 화면이 잠기지 않은 상태에서 5분 기다린 뒤 `C:\AxFieldKit\data\recordings\` 에 `.mkv` 가 생겼는지, 크기가 0이 아닌지, `data\activity\<날짜>.jsonl` 에 줄이 쌓이는지 본다. 사람에게 mkv 를 하나 열어 **전체 화면(모니터 2대면 둘 다)** 이 찍혔는지 확인해 달라고 한다. 업무 시간 밖이면 "대기(offhours)가 정상"으로 적고 ⏳ 로 표시, 다음 업무 시간에 확인할 일로 남긴다.
8. **결과 표 출력 + 보고서 저장.**

## 결과 표 형식 (그대로 출력, `C:\AxFieldKit\data\setup-report.md` 에도 저장)

```
| 단계 | 결과 | 비고 |
|---|---|---|
| 문법 검사 | ✅/❌ | 5개 파일 오류 수 |
| Git | ✅/❌ | |
| Claude Code | ✅ | 버전 (사람이 설치) |
| Tailscale | ✅/❌/⏳ | 상태·IP (사람이 키 입력) |
| OpenSSH | ✅/❌ | 공개키 등록 여부 |
| 화면 녹화 설치 | ✅/❌ | 작업 스케줄러·프로세스 |
| 트레이 아이콘 고정 | ✅/⏳ | 사람 확인 |
| 첫 녹화 파일 | ✅/❌/⏳ | 파일명·크기·전체 화면 여부 |
```
보고서 맨 위에 날짜·PC 이름·Windows 버전, 맨 아래에 "남은 일"(⏳/❌ 항목과 필요한 사람 조치)을 적는다. 비밀값은 어떤 형태로도 넣지 않는다.

## 철수·문제 해결
- 철수: `uninstall.ps1` (README 참고). 사용자가 요청할 때만 실행하고, 녹화 파일 삭제는 반드시 사람에게 묻는다.
- 막혔을 때 표와 매개변수는 `README.md` 의 "참고" 를 본다.
