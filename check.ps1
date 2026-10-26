# AX Field Kit - 동작 확인 (일반 PowerShell 가능)
param(
    [string]$InstallDir = 'C:\AxFieldKit',
    [string]$ExpectedTailnet = '', # 맥북 CurrentTailnet.Name. 생략/불일치/확인 불가는 실패.
    [string]$SshUser = ''          # 원격 통로 전용 계정 (install.ps1 -SshUser 와 같은 이름). 생략은 실패.
)
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$fail = 0
$unknown = 0
function Row($ok, $name, $detail) {
    if ($ok) { Write-Host ("[OK]   {0}  {1}" -f $name, $detail) -ForegroundColor Green }
    else { Write-Host ("[실패] {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}
# 권한 때문에 조회가 막힌 항목 (전용 계정·일반 사용자 SSH 세션 등). "없음"으로 오탐하지 않는다.
$DeniedText = '확인 불가(권한 — 관리자 PowerShell 에서 확인)'
function Unknown($name) { Write-Host ("[확인불가] {0}  {1}" -f $name, $script:DeniedText) -ForegroundColor Yellow; $script:unknown++ }
# 조회 결과와 '권한 등으로 실패했는지'를 함께 돌려준다. 오류 텍스트는 화면에 내보내지 않는다.
# '찾는 것이 없음'(ObjectNotFound) 오류는 실패가 아니라 빈 결과로 본다(관리자 실행 결과는 예전과 같음).
function Query([scriptblock]$Sb) {
    $out = @(); $bad = $false
    try {
        foreach ($x in @(& $Sb 2>&1)) {
            if ($x -is [System.Management.Automation.ErrorRecord]) { if ("$($x.CategoryInfo.Category)" -ne 'ObjectNotFound') { $bad = $true } }
            else { $out += $x }
        }
    } catch { if ("$($_.CategoryInfo.Category)" -ne 'ObjectNotFound') { $bad = $true } }
    [pscustomobject]@{ Value = $out; Denied = ($bad -and $out.Count -eq 0) }
}

# Claude Code
$c = (Get-Command claude.exe -ErrorAction SilentlyContinue).Source
if (-not $c -and (Test-Path "$env:USERPROFILE\.local\bin\claude.exe")) { $c = "$env:USERPROFILE\.local\bin\claude.exe" }
if ($c) { Row $true 'Claude Code' ((& $c --version 2>&1) -join ' ') } else { Row $false 'Claude Code' 'claude.exe 없음' }

# Tailscale
$t = (Get-Command tailscale.exe -ErrorAction SilentlyContinue).Source
if (-not $t -and (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) { $t = "$env:ProgramFiles\Tailscale\tailscale.exe" }
if ($t) {
    $st = (& $t status --json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue)
    $ip = (& $t ip -4 2>$null) | Select-Object -First 1
    $tailnet = [string]$st.CurrentTailnet.Name
    $expected = $ExpectedTailnet.Trim()
    $matchesTailnet = $expected -and $tailnet -and $tailnet -ieq $expected
    Row ($st.BackendState -eq 'Running' -and $ip -and $matchesTailnet) 'Tailscale' "상태=$($st.BackendState) 가입됨 테일넷=$tailnet IP=$ip 기대=$expected (기대 미지정/불일치/확인 불가는 실패)"
} else { Row $false 'Tailscale' 'tailscale.exe 없음' }

# OpenSSH (서비스 상태와 로컬 listen만 확인; 원격 접근 성공은 맥북에서 별도 확인)
# 일반 사용자의 네트워크 로그온(SSH)에서는 서비스 목록이 막혀 Get-Service 가 '없음'처럼 보이므로 서비스 등록(레지스트리)도 본다.
$q = Query { Get-Service sshd }
$ssh = $q.Value | Select-Object -First 1
$sshReg = $true
if (-not $ssh) { try { $null = Get-Item -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\sshd' -ErrorAction Stop } catch [System.Management.Automation.ItemNotFoundException] { $sshReg = $false } catch {} }
if (-not $ssh -and ($q.Denied -or $sshReg)) { Unknown 'OpenSSH 서비스' }
else { Row ($null -ne $ssh -and $ssh.Status -eq 'Running') 'OpenSSH 서비스' $(if ($ssh) { "$($ssh.Status)" } else { '미설치' }) }
$q = Query { Get-NetTCPConnection -LocalPort 22 -State Listen }
$listen = $q.Value | Select-Object -First 1
if ($q.Denied) { Unknown 'SSH tcp:22' }
else { Row ($null -ne $listen) 'SSH tcp:22' $(if ($listen) { '로컬 listen (Tailscale 정책/맥북 접근 별도 확인)' } else { 'listen 없음' }) }

# 원격 통로 전용 계정 (존재·그룹·잠김·우리 키 줄 수. 키 본문·암호는 출력하지 않음)
if (-not $SshUser.Trim()) { Row $false '전용 계정' '-SshUser 미지정 (전용 계정 확인 불가)' }
else {
    $su = $SshUser.Trim()
    $u = Get-LocalUser -Name $su -ErrorAction SilentlyContinue
    Row ($null -ne $u -and $u.Enabled) '전용 계정' $(if ($u) { "$su 사용=$($u.Enabled)" } else { "$su 없음 (사람이 new-access-account.ps1 실행)" })
    if ($u) {
        $a = [ADSI]"WinNT://$env:COMPUTERNAME/$su,user"
        $g = @($a.psbase.Invoke('Groups') | ForEach-Object {
            $b = $_.GetType().InvokeMember('objectSid', 'GetProperty', $null, $_, $null)
            (New-Object System.Security.Principal.SecurityIdentifier($b, 0)).Value
        })
        $inAdmins = $g -contains 'S-1-5-32-544'; $inUsers = $g -contains 'S-1-5-32-545'
        Row ($inUsers -and -not $inAdmins) '전용 계정 그룹' $(if ($inAdmins) { '경고: Administrators 소속 - 작업용 임시 부여가 아니면 회수 (소속 중에는 개인 authorized_keys 를 sshd 가 읽지 않음)' } elseif (-not $inUsers) { 'Users 그룹 아님' } else { 'Users (관리자 아님)' })
        $locked = [bool]$a.psbase.InvokeGet('IsAccountLocked')
        Row (-not $locked) '전용 계정 잠김' $(if ($locked) { '잠김 - docs/원격-통로.md 3-1 대로 해제만 (잠금 정책은 끄지 않음)' } else { '잠기지 않음' })
        $q = Query { Get-CimInstance Win32_UserProfile -Filter "SID='$($u.SID.Value)'" }
        $prof = $q.Value | Select-Object -First 1
        $profPath = if ($prof) { $prof.LocalPath } else { $null }
        $profDenied = $false
        if (-not $prof) {
            # CIM 이 막힌 세션(일반 사용자 SSH)은 ProfileList 레지스트리로 경로를 찾는다(Users 읽기 가능).
            try { $profPath = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($u.SID.Value)" -ErrorAction Stop).ProfileImagePath }
            catch [System.Management.Automation.ItemNotFoundException] {}
            catch { $profDenied = $true }
            if (-not $profPath -and $q.Denied) { $profDenied = $true }
            if ($profPath) { $prof = $true }
        }
        $ak = if ($profPath) { Join-Path $profPath '.ssh\authorized_keys' } else { $null }
        $n = $null
        if ($ak) { try { $n = @(Get-Content -LiteralPath $ak -ErrorAction Stop | Where-Object { $_ -cmatch '\sops-[A-Za-z0-9]+-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*-20[0-9]{6}\s*$' }).Count } catch {} }
        if (-not $prof -and $profDenied) { Unknown '전용 계정 공개키' }
        else { Row ($n -gt 0) '전용 계정 공개키' $(if (-not $prof) { '프로필 없음 (install.ps1 -SshUser 미실행)' } elseif ($null -eq $n) { '키 파일 없음/읽기 권한 없음 (관리자 PowerShell 에서 확인)' } else { "우리 키 $n 줄 (주석 ops-<고객>-<기기>-<날짜>, 본문 출력 안 함)" }) }
        # 전용 계정 비밀번호 SSH 끔 (install.ps1 의 sshd_config 표식 블록). install.ps1 과 같은 정적 검증(sshd-keyonly.ps1), 관리자만.
        # sshd -T -C 는 쓰지 않는다(관리자 PowerShell 에서 멈춤, 리허설). 실제 거부는 맥에서 비밀번호 SSH 시험으로 본다.
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $sshdLib = Join-Path $PSScriptRoot 'sshd-keyonly.ps1'
        if (-not $isAdmin) { Unknown '전용 계정 비밀번호 로그인 꺼짐' }
        elseif (-not (Test-Path -LiteralPath $sshdLib)) { Row $false '전용 계정 비밀번호 로그인 꺼짐' 'sshd-keyonly.ps1 없음 (키트 폴더 전체에서 실행)' }
        else {
            . $sshdLib
            $why = ''
            try {
                if (-not (Test-Path -LiteralPath $SshdExe)) { $why = 'sshd.exe 없음' }
                else {
                    $v = Test-AccessAccountKeyOnly (Read-SshdConfigText $SshdConfig) $su (Get-LocalGroupNames $su)
                    if (-not $v.Ok) { $why = $v.Reason }
                }
            } catch { $why = "sshd_config 확인 실패: $($_.Exception.Message)" }
            Row (-not $why) '전용 계정 비밀번호 로그인 꺼짐' $(if ($why) { "$why (install.ps1 -SshUser 다시 실행 또는 사람이 확인)" } else { 'sshd_config 정적 검증 OK (표식 블록 1개·뒤에 Match 밖 설정 줄 없음·앞선 Match 충돌 없음, 실제 거부는 맥에서 비밀번호 SSH 시험)' })
        }
    }
}

# 녹화
$q = Query { Get-ScheduledTask -TaskName 'AxFieldKitRecorder' }
$task = $q.Value | Select-Object -First 1
if ($q.Denied) { Unknown '자동 시작 작업' }
else { Row ($null -ne $task) '자동 시작 작업' $(if ($task) { "상태=$($task.State)" } else { '미등록' }) }
$q = Query { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" }
$rp = @($q.Value | Where-Object { $_.CommandLine -match 'recorder\.ps1' })
if ($q.Denied) { Unknown '녹화 프로그램' }
else { Row ($rp.Count -gt 0) '녹화 프로그램' $(if ($rp.Count) { "pid=$($rp[0].ProcessId)" } else { '실행 중 아님' }) }
$ff = Get-Process ffmpeg -ErrorAction SilentlyContinue
Write-Host ("       ffmpeg: {0}" -f $(if ($ff) { '녹화 중' } else { '대기 (업무 시간 밖/잠금/자리 비움이면 정상)' }))
$rec = Join-Path $InstallDir 'data\recordings'
$last = Get-ChildItem $rec -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($last) {
    $ageMin = [math]::Round(((Get-Date) - $last.LastWriteTime).TotalMinutes, 1)
    Write-Host ("       최근 파일: {0} ({1} MB, {2}분 전)" -f $last.Name, [math]::Round($last.Length / 1MB, 2), $ageMin)
} else { Write-Host '       녹화 파일 아직 없음 (업무 시간 안에서 몇 분 기다린 뒤 다시 확인)' }
$act = Get-ChildItem (Join-Path $InstallDir 'data\activity') -Filter *.jsonl -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($act) { Write-Host "       활동 기록: $($act.Name) ($($act.Length) bytes; 내용 출력 안 함)" }
$log = Join-Path $InstallDir 'data\recorder.log'
if (Test-Path $log) { Write-Host '       recorder.log 최근:'; Get-Content $log -Tail 3 -Encoding UTF8 | ForEach-Object { Write-Host "         $_" } }
$e = Join-Path $InstallDir 'data\ffmpeg-error.log'
if ((Test-Path $e) -and (Get-Item $e).Length -gt 0) { Write-Host '       ffmpeg-error.log:' -ForegroundColor Yellow; Get-Content $e -Tail 3 | ForEach-Object { Write-Host "         $_" } }

Write-Host ''
if ($unknown -gt 0) { Write-Host "$unknown 개 항목은 권한 때문에 확인하지 못했습니다 - 관리자 PowerShell 에서 check.ps1 을 다시 실행해 확인하세요." -ForegroundColor Yellow }
if ($fail -eq 0 -and $unknown -eq 0) { Write-Host '모두 정상' -ForegroundColor Green } elseif ($fail -eq 0) { exit 1 } else { Write-Host "$fail 개 항목 확인 필요" -ForegroundColor Red; exit 1 }
