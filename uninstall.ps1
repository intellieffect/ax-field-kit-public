# AX Field Kit - 철수 (관리자 PowerShell). 고객 데이터는 묻지 않고 지우지 않는다.
param(
    [string]$InstallDir = 'C:\AxFieldKit',
    [switch]$KeepData,        # 녹화 파일 보존 (묻지 않음)
    [switch]$DeleteData,      # 녹화 파일 삭제 (묻지 않음)
    [switch]$KeepSsh,         # sshd 서비스·방화벽을 그대로 둠 (우리 공개키는 항상 제거, 서비스·방화벽은 사전 기록대로 사람이 복구)
    [string]$SshUser = '',    # 원격 통로 전용 계정 (install.ps1 -SshUser 와 같은 이름). 생략하면 전용 계정 키·계정 회수를 건너뜀
    [switch]$KeepSshUser      # 전용 계정·프로필을 남김 (묻지 않음). 기본은 사람에게 삭제 여부를 물음
)
$ErrorActionPreference = 'Continue'
function Step($m) { Write-Host "== $m" -ForegroundColor Cyan }
# 우리 키 줄: 기기별 주석 ops-<고객>-<기기>-<날짜>, 또는 옛 판의 고정 표식 ax-field-kit (호환)
$OurKeyPattern = '\sops-[A-Za-z0-9]+-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*-20[0-9]{6}\s*$|\sax-field-kit\s*$'
function Remove-OurKeyLines([string]$Path, [switch]$DeleteIfEmpty) {
    if (-not (Test-Path -LiteralPath $Path)) { Write-Host "  없음: $Path"; return }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    # UTF-16 이면 ASCII 로 읽을 때 우리 줄을 못 알아보므로 "없음" 이라고 하지 않고 사람에게 넘긴다(파일은 건드리지 않음).
    $isBE = $bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF
    $isLE = $bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE
    if ($isBE -or $isLE -or ($bytes -contains [byte]0)) {
        $enc = if ($isBE) { [System.Text.Encoding]::BigEndianUnicode } else { [System.Text.Encoding]::Unicode }
        $u16 = @(($enc.GetString($bytes).TrimStart([char]0xFEFF) -split "`r?`n") | Where-Object { $_ -cmatch $OurKeyPattern }).Count
        Write-Host "  $Path 는 UTF-16 파일이라 자동으로 고치지 않습니다 - 사람이 확인하세요. 주석이 ops-<고객>- 또는 ax-field-kit 인 줄로 보이는 것 $u16 개(0개여도 직접 열어 확인)." -ForegroundColor Yellow
        return
    }
    $lines = @([System.Text.Encoding]::ASCII.GetString($bytes) -split "`r?`n")
    $ours = @($lines | Where-Object { $_ -cmatch $OurKeyPattern })
    if ($ours.Count -eq 0) { Write-Host "  우리 키 줄 없음: $Path"; return }
    # ASCII 가 아닌 글자(고객의 한글 주석 등)가 있으면 다시 쓰다 깨질 수 있으므로 지우지 않고 사람에게 넘긴다.
    if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) {
        Write-Host "  $Path 에 ASCII 가 아닌 글자가 있어 자동으로 고치지 않습니다. 주석이 ops-<고객>- 또는 ax-field-kit 인 줄 $($ours.Count)개를 사람이 직접 지우세요." -ForegroundColor Yellow
        return
    }
    $keep = @($lines | Where-Object { $_ -and $_ -cnotmatch $OurKeyPattern })
    if ($keep.Count -eq 0 -and $DeleteIfEmpty) { Remove-Item -LiteralPath $Path -Force }
    else { [System.IO.File]::WriteAllText($Path, $(if ($keep.Count) { ($keep -join "`r`n") + "`r`n" } else { '' }), [System.Text.Encoding]::ASCII) }
    Write-Host "  우리 키 $($ours.Count)줄 제거: $Path (다른 줄 $($keep.Count)개 보존)"
}
# install.ps1 이 sshd_config 끝에 넣은 표식 블록(전용 계정 비밀번호 SSH 끄기) 중 -SshUser 계정의 것만 지운다. 고객의 다른 줄,
# 다른 전용 계정의 블록은 그대로(그 계정의 비밀번호 SSH 가 다시 켜지지 않게, 리허설 N2). 표식에 계정 이름(소문자)이 들어 있다.
# 우리 계정 전용 설정이므로 -KeepSsh 여도 지운다. -SshUser 가 없으면 아무 블록도 지우지 않는다. 반환: 지웠으면 $true.
# sshd -t 는 sshd-keyonly.ps1 의 시간 제한 실행(15초)으로 부른다.
$SshdLib = Join-Path $PSScriptRoot 'sshd-keyonly.ps1'
if (Test-Path -LiteralPath $SshdLib) { . $SshdLib }
function Remove-OurSshdBlock([string]$User) {
    $cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
    $exe = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
    if (-not (Get-Command Test-SshdConfig -ErrorAction SilentlyContinue)) { Write-Host "  sshd-keyonly.ps1 이 없어 sshd_config 는 건드리지 않습니다 - ax-field-kit 표식 블록을 사람이 지우고 sshd -t 로 확인하세요." -ForegroundColor Yellow; return $false }
    if (-not (Test-Path -LiteralPath $cfg)) { Write-Host "  없음: $cfg"; return $false }
    $u = $User.Trim().ToLowerInvariant()
    if (-not $u) { Write-Host '  -SshUser 미지정: sshd_config 의 전용 계정 표식 블록은 그대로 둡니다 (지우려면 -SshUser <계정> 으로 다시 실행).' -ForegroundColor Yellow; return $false }
    $bytes = [System.IO.File]::ReadAllBytes($cfg)
    if (($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) -or ($bytes -contains [byte]0)) {
        Write-Host "  $cfg 는 UTF-16 파일이라 자동으로 고치지 않습니다 - '# BEGIN ax-field-kit access-account $u' 부터 '# END ax-field-kit access-account $u' 까지를 사람이 지우세요." -ForegroundColor Yellow
        return $false
    }
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    # 잘못된 UTF-8(예: CP949 한글 주석)이면 다시 쓰다 깨지므로 건드리지 않는다.
    try { $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes) }
    catch { Write-Host "  $cfg 에 UTF-8 이 아닌 글자가 있어 자동으로 고치지 않습니다 - ax-field-kit 표식 블록을 사람이 지우세요." -ForegroundColor Yellow; return $false }
    if ($hasBom) { $text = $text.Substring(1) }
    $ue = [regex]::Escape($u)
    $rx = New-Object System.Text.RegularExpressions.Regex(('^# BEGIN ax-field-kit access-account ' + $ue + '(?: [^\r\n]*)?\r?\n(?:(?!# (?:BEGIN|END) ax-field-kit)[^\r\n]*\r?\n)*?# END ax-field-kit access-account ' + $ue + '[ \t]*(?:\r?\n|$)'), ([System.Text.RegularExpressions.RegexOptions]::Multiline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
    $n = $rx.Matches($text).Count
    $rest = $rx.Replace($text, '')
    $others = @([regex]::Matches($rest, '(?m)^# BEGIN ax-field-kit access-account (\S+)') | ForEach-Object { $_.Groups[1].Value })
    $otherNote = if ($others.Count) { " / 다른 전용 계정 블록 $($others.Count) 개는 남김: $($others -join ', ')" } else { '' }
    if ($n -eq 0) {
        if ($text -imatch ('(?m)^# (BEGIN|END) ax-field-kit access-account ' + $ue + '(\s|$)')) { Write-Host "  $cfg 에 $u 의 짝이 맞지 않는 ax-field-kit 표식이 있습니다 - 자동으로 고치지 않습니다. 사람이 확인하세요." -ForegroundColor Yellow }
        else { Write-Host "  sshd_config 에 $u 의 표식 블록 없음$otherNote" }
        return $false
    }
    $backup = "$cfg.bak-axfieldkit-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $cfg -Destination $backup -Force
    [System.IO.File]::WriteAllText($cfg, $rest, (New-Object System.Text.UTF8Encoding($hasBom)))
    if (Test-Path -LiteralPath $exe) {
        $t = Test-SshdConfig
        if (-not $t.Ok) {
            Copy-Item -LiteralPath $backup -Destination $cfg -Force
            Write-Host "  sshd -t 문법 검사 실패로 sshd_config 를 원본으로 되돌렸습니다 (백업 $backup). 사람이 확인하세요. 오류: $($t.Text)" -ForegroundColor Red
            return $false
        }
    }
    Write-Host "  sshd_config 의 $u 표식 블록 $n 개 제거 (이 계정 비밀번호 SSH 끄기 해제, 다른 줄 보존, 백업 $backup)$otherNote"
    return $true
}

Step '녹화 중지 + 자동 시작 제거'
Stop-ScheduledTask -TaskName 'AxFieldKitRecorder' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'AxFieldKitRecorder' -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'recorder\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name='ffmpeg.exe'" | Where-Object { $_.ExecutablePath -like "$InstallDir*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Step '녹화 파일'
$data = Join-Path $InstallDir 'data'
$del = $false
if ($DeleteData) { $del = $true }
elseif (-not $KeepData -and (Test-Path $data)) {
    $size = [math]::Round((Get-ChildItem $data -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB)
    $a = Read-Host "  $data ($size MB) 의 녹화/활동 기록을 삭제할까요? (y=삭제 / 그 외=보존)"
    $del = ($a -match '^[yY]')
}
if ($del) {
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '  설치 폴더와 녹화 데이터를 삭제했습니다.'
} else {
    foreach ($f in 'bin', 'recorder.ps1', 'config.json') { Remove-Item (Join-Path $InstallDir $f) -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host "  녹화 데이터는 보존했습니다: $data (필요 시 수동 삭제)"
}

Step 'OpenSSH 정리 (전용 계정 키 -> 관리자 키 -> 전용 계정·프로필 -> sshd_config 표식 블록)'
$acct = $null
if ($SshUser.Trim()) {
    $u = Get-LocalUser -Name $SshUser.Trim() -ErrorAction SilentlyContinue
    if ($u) { $acct = $u } else { Write-Host "  전용 계정 $SshUser 없음 - 계정 키·계정 회수 건너뜀" }
} else { Write-Host '  -SshUser 미지정: 전용 계정 키·계정 회수를 건너뜁니다 (계정이 있었다면 -SshUser 로 다시 실행).' -ForegroundColor Yellow }
$prof = $null
$acctPending = $false   # 프로필이 로드돼 있어 계정·프로필 삭제를 미룬 경우
if ($acct) {
    # 1) 전용 계정의 키 파일부터 (계정을 지우기 전에 해야 경로가 남아 있다)
    $prof = Get-CimInstance Win32_UserProfile -Filter "SID='$($acct.SID.Value)'" -ErrorAction SilentlyContinue
    if ($prof) { Remove-OurKeyLines (Join-Path $prof.LocalPath '.ssh\authorized_keys') }
    else { Write-Host "  전용 계정 프로필 없음 - 계정 키 파일 없음" }
}
# 2) 관리자 키 파일 (옛 판의 ax-field-kit 표식 줄, 호환). 고객의 다른 줄은 보존
Remove-OurKeyLines (Join-Path $env:ProgramData 'ssh\administrators_authorized_keys') -DeleteIfEmpty
# 3) 전용 계정·프로필 삭제 (사람 확인). new-access-account.ps1 이 만든 계정만 대상
if ($acct) {
    $delUser = $false
    if ($acct.Description -notlike '*Remote access (ax-field-kit)*') {
        Write-Host "  $($acct.Name) 은 new-access-account.ps1 이 만든 계정이 아니라(설명 표식 없음) 자동 삭제하지 않습니다. 회수 기록을 보고 사람이 직접 삭제하세요." -ForegroundColor Yellow
    } elseif ($acct.Name -ieq $env:USERNAME) {
        Write-Host '  지금 실행 중인 계정이라 삭제하지 않습니다.' -ForegroundColor Yellow
    } elseif (-not $KeepSshUser) {
        $where = if ($prof) { $prof.LocalPath } else { '프로필 없음' }
        $a = Read-Host "  전용 계정 $($acct.Name) 과 프로필 폴더($where)를 삭제할까요? (y=삭제 / 그 외=보존)"
        $delUser = ($a -match '^[yY]')
    }
    if ($delUser) {
        if ($prof -and $prof.Loaded) {
            # 접속을 끊은 뒤에도 Windows 가 재부팅 전까지 프로필을 잡고 있는 경우가 있다(리허설 실측). 강제 언로드·프로세스 종료는 하지 않는다.
            Write-Host '  프로필이 아직 로드돼 있습니다(접속·로그인 중이거나, 접속을 끊은 뒤에도 Windows 가 프로필을 잡고 있음). 프로필·계정을 지우지 않았습니다.' -ForegroundColor Yellow
            $acctPending = $true
        } else {
            $ok = $true
            if ($prof) {
                try { $prof | Remove-CimInstance -ErrorAction Stop; Write-Host "  프로필 삭제: $($prof.LocalPath)" }
                catch { $ok = $false; Write-Host "  프로필 삭제 실패: $($_.Exception.Message) - 계정은 지우지 않았습니다(프로필이 고아로 남지 않게)." -ForegroundColor Red }
            }
            if ($ok) {
                try { Remove-LocalUser -SID $acct.SID -ErrorAction Stop; Write-Host "  전용 계정 삭제: $($acct.Name)" }
                catch { Write-Host "  계정 삭제 실패: $($_.Exception.Message)" -ForegroundColor Red }
            }
        }
    } else { Write-Host "  전용 계정 $($acct.Name) 은 남겨 두었습니다 (우리 키는 위에서 제거)." }
}
# 4) sshd_config 의 이 계정 표식 블록 (-KeepSsh 여도 지움, 계정이 이미 없어도 지움). sshd 가 계속 도는 경우에만 재시작해 반영
$cfgChanged = Remove-OurSshdBlock $SshUser
if ($cfgChanged -and $KeepSsh -and (Get-Service sshd -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })) {
    try { Restart-Service sshd -ErrorAction Stop; Write-Host '  sshd 재시작 (설정 반영)' }
    catch { Write-Host "  sshd 재시작 실패: $($_.Exception.Message) - 사람이 확인하세요." -ForegroundColor Red }
}
# 5) 서비스·방화벽
if ($KeepSsh) { Write-Host '  -KeepSsh: sshd·방화벽은 그대로 둡니다. setup-report.md 의 사전 기록대로 서비스 시작형식·OpenSSH-Server-In-TCP 규칙·AxFieldKit-SSH 규칙을 사람이 복구하세요.' }
else {
    Get-NetFirewallRule -Name 'AxFieldKit-SSH' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    if (Get-Service sshd -ErrorAction SilentlyContinue) {
        Stop-Service sshd -ErrorAction SilentlyContinue; Set-Service sshd -StartupType Disabled
        Write-Host '  sshd 중지 + 사용 안 함 (고객이 이전부터 쓰던 SSH 였다면 -KeepSsh 로 다시 실행)'
    }
}
if ($acctPending) {
    $done = if ($KeepSsh) { '키 회수는 이미 끝남, sshd·방화벽은 -KeepSsh 안내대로' } else { '키·방화벽 회수는 이미 끝남' }
    Write-Host "  전용 계정 $($acct.Name) 삭제가 남았습니다: PC를 다시 시작한 뒤 uninstall 을 다시 실행하세요($done). 다시 실행할 때 -SshUser $($acct.Name) 을 붙이세요." -ForegroundColor Yellow
}

Step 'Tailscale 로그아웃'
$t = (Get-Command tailscale.exe -ErrorAction SilentlyContinue).Source
if (-not $t -and (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) { $t = "$env:ProgramFiles\Tailscale\tailscale.exe" }
if ($t) { $ErrorActionPreference = 'Continue'; & $t logout 2>&1 | Out-Host; Write-Host '  (기기 삭제는 Tailscale 관리 콘솔에서도 확인)' } else { Write-Host '  Tailscale 없음 - 건너뜀' }

Step 'Claude Code 로그아웃 안내'
Write-Host '  이 PC 에서 claude 를 실행해 /logout 하세요. (프로그램 자체 제거: Remove-Item $env:USERPROFILE\.local\bin\claude.exe, $env:USERPROFILE\.local\share\claude)'
Write-Host ''
if ($acctPending) { Write-Host "철수 미완료: 전용 계정 $($acct.Name) 이 남아 있습니다. PC를 다시 시작한 뒤 uninstall 을 -SshUser $($acct.Name) 로 다시 실행하세요($done)." -ForegroundColor Yellow }
else { Write-Host '철수 완료. Tailscale/Git 프로그램 자체는 남겨 둡니다(필요 시 설정 > 앱에서 제거).' -ForegroundColor Green }
