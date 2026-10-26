# AX Field Kit - 현장 설치 진입점 (Windows 10/11, 관리자 PowerShell)
# OpenSSH -> Tailscale(가입) -> Git for Windows -> Claude Code -> 화면 녹화. 다시 실행해도 안전(이미 있으면 건너뜀).
param(
    [string]$Customer = '',                      # customers\<이름>\config.json 사용
    [string]$TsTag = '',                         # Tailscale 태그 예: tag:ax-field (키에 태그 권한 필요)
    [string]$ExpectedTailnet = '',               # 맥북 CurrentTailnet.Name과 일치해야 함 (가입 단계 필수)
    [string]$TsHostname = '',                    # Tailscale 기기 이름 (기본: 컴퓨터 이름)
    [string]$InstallDir = 'C:\AxFieldKit',
    [switch]$SkipGit,
    [switch]$SkipClaude,
    [switch]$SkipTailscale,
    [switch]$SkipRecorder,
    [switch]$SkipSsh,                            # OpenSSH 서버 설치 건너뜀 (기본은 켬: Tailscale 대역에서만 허용, 파일 회수 경로)
    [string]$SshPublicKey = '',                  # 우리 쪽 SSH 공개키 한 줄 (공개키라 비밀 아님) -> 전용 계정의 .ssh\authorized_keys
    [string]$SshUser = '',                       # 원격 통로 전용 일반 계정 (사람이 new-access-account.ps1 로 먼저 만듦). -SshPublicKey 와 함께 필수
    [string]$SshKeyComment = '',                 # 키 주석 ops-<고객>-<기기>-<날짜> (생략 시 공개키 줄의 주석 사용)
    [switch]$EnableSsh,                          # (구 옵션, 이제 기본값이라 무시)
    [switch]$ContinueOnError                     # 구 옵션: 안전을 위해 이제 실패 시 항상 중단
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$here = $PSScriptRoot
$results = New-Object System.Collections.ArrayList

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Find-Tool($name, $extra) {
    Refresh-Path
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in $extra) { if (Test-Path $p) { return $p } }
    return $null
}
$GitExe       = { Find-Tool 'git.exe' @("$env:ProgramFiles\Git\cmd\git.exe") }
$ClaudeExe    = { Find-Tool 'claude.exe' @("$env:USERPROFILE\.local\bin\claude.exe") }
$TailscaleExe = { Find-Tool 'tailscale.exe' @("$env:ProgramFiles\Tailscale\tailscale.exe") }

function Invoke-Step([string]$Name, [scriptblock]$Body) {
    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    try {
        $note = & $Body
        [void]$results.Add([pscustomobject]@{ Step = $Name; Ok = $true; Note = "$note" })
        Write-Host "  -> OK $note" -ForegroundColor Green
    } catch {
        $msg = $_.Exception.Message
        Write-Host "  -> 실패: $msg" -ForegroundColor Red
        [void]$results.Add([pscustomobject]@{ Step = $Name; Ok = $false; Note = $msg })
        # 권한/인증/보안 거부를 재시도하거나 다음 단계로 넘어가지 않는다.
        Show-Summary; exit 1
    }
}
function Show-Summary {
    Write-Host ""
    Write-Host '================ 설치 요약 ================' -ForegroundColor Cyan
    foreach ($r in $results) {
        $mark = if ($r.Ok) { '[OK]  ' } else { '[실패]' }
        $color = if ($r.Ok) { 'Green' } else { 'Red' }
        Write-Host ("{0} {1}  {2}" -f $mark, $r.Step, $r.Note) -ForegroundColor $color
    }
    Write-Host '==========================================='
    Write-Host '확인:  powershell -ExecutionPolicy Bypass -File .\check.ps1 -ExpectedTailnet "<맥북 CurrentTailnet.Name>" -SshUser <전용계정>' -ForegroundColor Cyan
}
# 네이티브 명령 출력 (PS 5.1: EAP=Stop 에서 stderr 한 줄이 예외가 되는 것을 막음)
function Get-NativeOutput([string]$Exe, [string[]]$CmdArgs) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { return ((& $Exe @CmdArgs 2>&1 | ForEach-Object { "$_" }) -join ' ').Trim() } finally { $ErrorActionPreference = $old }
}
function Install-WithWinget($id) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget 이 없습니다 (Microsoft Store 의 "앱 설치 관리자" 업데이트 필요). README 의 수동 설치를 보세요.' }
    & winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
    # 이미 설치됨/업데이트 없음 종료 코드 두 값(0x8A15002B, 0x8A150061)은 정상으로 취급
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -notin -1978335189, -1978335135) { throw "winget 설치 실패 ($id, 종료코드 $LASTEXITCODE)" }
}
# ---- 원격 통로 전용 계정 (계정은 사람이 new-access-account.ps1 로 만든다) ----
function Test-KeyComment([string]$c) { return ($c -cmatch '^ops-[A-Za-z0-9]+-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*-20[0-9]{6}$') }
function Get-GroupSids([string]$Name) {
    # Get-LocalGroupMember 는 고아 SID 가 있는 PC 에서 실패하므로 ADSI 로 계정의 그룹 SID 를 읽는다.
    $a = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,user"
    @($a.psbase.Invoke('Groups') | ForEach-Object {
        $b = $_.GetType().InvokeMember('objectSid', 'GetProperty', $null, $_, $null)
        (New-Object System.Security.Principal.SecurityIdentifier($b, 0)).Value
    })
}
function Get-AccessAccount([string]$Name) {
    if ($Name -cnotmatch '^[A-Za-z][A-Za-z0-9_-]{0,19}$') { throw "전용 계정 이름 형식이 올바르지 않습니다: $Name" }
    $u = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    if (-not $u) { throw "전용 계정 $Name 이 없습니다. 사람이 새 관리자 PowerShell 에서 .\new-access-account.ps1 -UserName $Name 을 실행한 뒤 다시 하세요 (Claude 는 대신 만들지 않음)." }
    if (-not $u.Enabled) { throw "전용 계정 $Name 이 사용 안 함 상태입니다. 사람이 확인하세요." }
    $g = Get-GroupSids $Name
    if ($g -contains 'S-1-5-32-544') { throw "전용 계정 $Name 이 Administrators 소속입니다. sshd 는 관리자 계정의 개인 authorized_keys 를 읽지 않고 최소 권한도 아닙니다. 그룹 변경은 사람이 결정합니다." }
    if ($g -notcontains 'S-1-5-32-545') { throw "전용 계정 $Name 이 Users 그룹 소속이 아닙니다. 사람이 확인하세요." }
    [pscustomobject]@{ Name = $u.Name; Sid = $u.SID.Value }
}
function Get-AccessProfilePath($Acct) {
    # 한 번도 로그인하지 않은 계정은 프로필이 없다. 폴더를 직접 만들면 첫 로그인 때 다른 경로의 프로필이 생기므로 Windows API 로 만든다(암호 불필요).
    $p = Get-CimInstance Win32_UserProfile -Filter "SID='$($Acct.Sid)'"
    if (-not $p) {
        if (-not ('AxFieldKit.UserEnv' -as [type])) {
            Add-Type -Namespace AxFieldKit -Name UserEnv -MemberDefinition @'
[DllImport("userenv.dll", CharSet = CharSet.Unicode)]
public static extern int CreateProfile(string pszUserSid, string pszUserName, System.Text.StringBuilder pszProfilePath, uint cchProfilePath);
'@
        }
        $sb = New-Object System.Text.StringBuilder 260
        $hr = [AxFieldKit.UserEnv]::CreateProfile($Acct.Sid, $Acct.Name, $sb, 260)
        # 0x800700B7 = 이미 있음
        if ($hr -ne 0 -and $hr -ne -2147024713) { throw ("전용 계정 프로필 생성 실패 (HRESULT 0x{0:X8})" -f $hr) }
        $p = Get-CimInstance Win32_UserProfile -Filter "SID='$($Acct.Sid)'"
    }
    if (-not $p -or -not $p.LocalPath) { throw "전용 계정 $($Acct.Name) 의 프로필 경로를 찾지 못했습니다." }
    return $p.LocalPath
}
function Add-KeyLine([string]$Path, [string]$Line) {
    # 기존 줄은 다시 쓰지 않고 끝에 ASCII 한 줄만 덧붙인다. UTF-16 파일이면 덧붙이면 깨지므로 멈춘다.
    $prefix = ''
    if ((Test-Path -LiteralPath $Path) -and (Get-Item -LiteralPath $Path).Length -gt 0) {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) { throw "$Path 가 UTF-16 입니다. sshd 가 읽지 못하는 형식이라 사람이 확인해야 합니다." }
        if ($bytes[-1] -ne 10) { $prefix = "`r`n" }
    }
    [System.IO.File]::AppendAllText($Path, $prefix + $Line + "`r`n", [System.Text.Encoding]::ASCII)
}
# ---- 전용 계정만 sshd 비밀번호 로그인 끄기 ----
# 틀린 암호 10회로 계정이 잠기면 키 로그인도 끊기므로(리허설 실측) 전용 계정은 키로만 들어오게 한다.
# sshd_config 끝에 표식으로 감싼 Match 블록 하나만 덧붙인다. 고객의 다른 줄은 다시 쓰지 않는다.
# Match 블록은 다음 Match 줄이나 파일 끝까지이므로, 기본 파일 끝의 'Match Group administrators' 뒤에 붙여도 그 블록 안으로 들어가지 않는다.
# 표식·정적 검증·시간 제한 실행은 sshd-keyonly.ps1 (check.ps1·uninstall.ps1 과 같이 씀).
$SshdLib = Join-Path $here 'sshd-keyonly.ps1'
if (-not (Test-Path -LiteralPath $SshdLib)) { Write-Host "sshd-keyonly.ps1 이 없습니다 ($SshdLib). 키트 폴더 전체를 복사해 다시 실행하세요." -ForegroundColor Red; exit 1 }
. $SshdLib
function Set-AccessAccountKeyOnly([string]$User) {
    # 반환: 요약에 붙일 문구. 실패하면 sshd_config 를 바꾸지 않거나 원본으로 되돌리고 throw.
    $u = $User.ToLowerInvariant()   # Windows OpenSSH 는 계정 이름을 소문자로 맞춰 비교한다
    if (-not (Test-Path -LiteralPath $SshdExe)) { throw "sshd.exe 를 찾지 못했습니다 ($SshdExe)" }
    if (-not (Test-Path -LiteralPath $SshdConfig)) { throw "$SshdConfig 가 없습니다 (sshd 를 한 번 시작하면 생김). 사람이 확인하세요." }
    $text = Read-SshdConfigText $SshdConfig
    $groups = Get-LocalGroupNames $User
    if (@($text -split "`r?`n" | Where-Object { $_.Trim() -ceq (Get-SshdBlockBegin $u) }).Count -gt 0) {
        $v = Test-AccessAccountKeyOnly $text $u $groups
        if (-not $v.Ok) { throw "sshd_config 에 우리 표식 블록이 있지만 기대와 다릅니다: $($v.Reason). 자동으로 고치지 않습니다 - 사람이 확인하세요." }
        return ', 비밀번호 SSH 이미 꺼짐 (표식 블록 있음, 정적 검증 OK)'
    }
    $raw = [System.IO.File]::ReadAllBytes($SshdConfig)
    $prefix = if ($raw.Length -gt 0 -and $raw[-1] -ne 10) { "`r`n" } else { '' }
    $block = $prefix + (@((Get-SshdBlockBegin $u), "Match User $u", '    PasswordAuthentication no', (Get-SshdBlockEnd $u)) -join "`r`n") + "`r`n"
    # 덧붙인 뒤의 모습을 먼저 정적으로 검증한다. 앞선 고객 Match 블록이 이 계정에 먼저 적용되면 파일을 바꾸지 않고 멈춘다.
    $v = Test-AccessAccountKeyOnly ($text + $block) $u $groups
    if (-not $v.Ok) { throw "블록을 넣어도 $u 의 비밀번호 로그인이 꺼진다고 확인할 수 없어 sshd_config 를 바꾸지 않았습니다: $($v.Reason) - 사람이 확인하세요." }
    $backup = "$SshdConfig.bak-axfieldkit-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $SshdConfig -Destination $backup -Force
    [System.IO.File]::AppendAllText($SshdConfig, $block, [System.Text.Encoding]::ASCII)
    $t = Test-SshdConfig
    if (-not $t.Ok) {
        Copy-Item -LiteralPath $backup -Destination $SshdConfig -Force
        throw "sshd -t 문법 검사 실패로 sshd_config 를 원본으로 되돌렸습니다 (백업 $backup). 오류: $($t.Text)"
    }
    Restart-Service sshd
    ", 비밀번호 SSH 꺼짐 (Match User $u, 정적 검증 OK - 실제 거부는 맥에서 비밀번호 SSH 로 확인, 백업 $backup)"
}

# ---------------- 0. 사전 점검 ----------------
Invoke-Step '사전 점검' {
    $os = Get-CimInstance Win32_OperatingSystem
    if ([Environment]::OSVersion.Version.Major -lt 10) { throw "Windows 10 이상이 필요합니다 ($($os.Caption))" }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw '관리자 권한이 아닙니다. 시작 메뉴에서 PowerShell 을 "관리자 권한으로 실행" 후 다시 하세요.' }
    $free = (Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free / 1GB
    if ($free -lt 5) { throw ("디스크 여유 공간 부족: {0:N1} GB (최소 5GB)" -f $free) }
    try { $null = Invoke-WebRequest -Uri 'https://pkgs.tailscale.com' -UseBasicParsing -Method Head -TimeoutSec 15 }
    catch { throw "인터넷(HTTPS) 연결 실패: $($_.Exception.Message) - 고객사 방화벽/프록시 확인" }
    $pol = Get-ExecutionPolicy -Scope Process
    if ($pol -eq 'Restricted' -or $pol -eq 'AllSigned') { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force }
    "$($os.Caption), 여유 $([math]::Round($free)) GB, 사용자 $env:USERNAME"
}

# 사전 점검 실패는 ContinueOnError 이어도 설치를 진행하지 않는다.
if (($results | Where-Object { -not $_.Ok }).Count -gt 0) { Show-Summary; exit 1 }

# ---------------- 1. OpenSSH (통로 먼저) ----------------
if (-not $SkipSsh) {
    Invoke-Step 'OpenSSH 서버 (Tailscale 대역 전용)' {
        if ($SshPublicKey) {
        # 키 본문만 ASCII로 정규화하고 줄 끝에 기기별 주석을 붙인다(한글 주석/사용자 이름을 키 파일에 넣지 않음).
        if ($SshPublicKey.Trim() -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521))\s+([A-Za-z0-9+/]+={0,2})(?:\s+(.*))?$') { throw 'SSH 공개키 형식이 올바르지 않습니다.' }
        $keyBody = $Matches[1] + ' ' + $Matches[2]
        $comment = if ($SshKeyComment.Trim()) { $SshKeyComment.Trim() } else { "$($Matches[3])".Trim() }
        if (-not (Test-KeyComment $comment)) { throw "키 주석은 ops-<고객>-<기기>-<날짜8자리> (영문·숫자·- 만) 이어야 합니다. -SshKeyComment 로 지정하세요. 받은 값: '$comment'" }
        if (-not $SshUser.Trim()) { throw '-SshUser 가 없습니다. 사람이 새 관리자 PowerShell 에서 .\new-access-account.ps1 -UserName <전용계정> 을 먼저 실행한 뒤 그 이름을 지정하세요.' }
        $acct = Get-AccessAccount $SshUser.Trim()
        # 실패할 수 있는 준비(프로필 생성·경로 확인·.ssh 폴더)는 sshd·방화벽을 바꾸기 전에 끝낸다.
        $userHome = Get-AccessProfilePath $acct
        $sshDir = Join-Path $userHome '.ssh'
        if (-not (Test-Path -LiteralPath $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }
        $ak = Join-Path $sshDir 'authorized_keys'
        }
        $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
        if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
        Set-Service -Name sshd -StartupType Automatic
        Start-Service sshd
        Get-NetFirewallRule -Name 'AxFieldKit-SSH' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        # 기본 sshd 규칙은 전체 허용이므로 끄고, Tailscale 대역(100.64.0.0/10)만 허용
        Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
        New-NetFirewallRule -Name 'AxFieldKit-SSH' -DisplayName 'AX Field Kit SSH (Tailscale only)' -Direction Inbound `
            -Protocol TCP -LocalPort 22 -RemoteAddress '100.64.0.0/10' -Action Allow | Out-Null
        $keyNote = ''
        if ($SshPublicKey) {
            # 관리자 키 파일(administrators_authorized_keys)이 아니라 전용 계정의 개인 키 파일($ak, 위에서 준비)에 넣는다.
            # 줄 끝의 ops-<고객>-<기기>-<날짜> 주석으로 uninstall 이 우리 줄만 제거. 고객의 다른 줄은 건드리지 않는다.
            $already = (Test-Path -LiteralPath $ak) -and (Select-String -LiteralPath $ak -SimpleMatch -Pattern $keyBody -Quiet)
            if (-not $already) { Add-KeyLine $ak ($keyBody + ' ' + $comment) }
            else {
                # 이미 있는 줄은 다시 쓰지 않으므로 요약에는 파일에 실제로 남아 있는 주석을 적는다.
                $line = @(Get-Content -LiteralPath $ak | Where-Object { $_.Contains($keyBody) }) | Select-Object -First 1
                $oldComment = if ($line) { $line.Substring($line.IndexOf($keyBody) + $keyBody.Length).Trim() } else { '' }
                if (-not $oldComment) { $oldComment = '(주석 없음)' }
            }
            # 소유자 = 전용 계정, 권한 = 그 계정·SYSTEM·Administrators 만 (sshd 가 그 밖의 쓰기 권한이 있으면 키 파일을 거부)
            foreach ($p in $sshDir, $ak) {
                $inherit = if ($p -eq $sshDir) { '(OI)(CI)' } else { '' }
                & icacls $p /inheritance:r /grant:r "*$($acct.Sid):$($inherit)F" "*S-1-5-18:$($inherit)F" "*S-1-5-32-544:$($inherit)F" | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "SSH 키 ACL 설정 실패 ($p)" }
                & icacls $p /setowner "*$($acct.Sid)" | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "SSH 키 소유자 설정 실패 ($p)" }
            }
            $keyNote = if ($already) {
                ", 공개키 이미 등록됨 (계정 $($acct.Name), 기존 주석 $oldComment" + $(if ($oldComment -cne $comment) { " - 요청한 주석 $comment 은 반영하지 않음, 키 줄은 그대로" } else { '' }) + ')'
            } else { ", 공개키 등록 (계정 $($acct.Name), 주석 $comment)" }
            # 키 등록이 끝난 뒤 전용 계정만 비밀번호 SSH 를 끈다(키 로그인은 그대로). sshd -t 실패면 원복하고 멈춤.
            $keyNote += Set-AccessAccountKeyOnly $acct.Name
        }
        'sshd 켜짐 (100.64.0.0/10 에서만 접속 가능)' + $(if ($SshPublicKey) { $keyNote } else { ' - 공개키 미등록: -SshUser·-SshPublicKey 로 다시 실행 (비밀번호 통로로 쓰지 않음)' })
    }
}

# ---------------- 2. Tailscale ----------------
if (-not $SkipTailscale) {
    Invoke-Step 'Tailscale 설치' {
        $t = & $TailscaleExe
        if ($t) { return "이미 설치됨 ($t)" }
        Install-WithWinget 'Tailscale.Tailscale'
        if (-not (& $TailscaleExe)) { throw 'Tailscale 설치 후 tailscale.exe 를 찾지 못했습니다.' }
        '설치 완료'
    }
    Invoke-Step 'Tailscale 가입' {
        $t = & $TailscaleExe
        if (-not $t) { throw 'tailscale.exe 없음 (이전 단계 실패)' }
        if (-not $ExpectedTailnet.Trim()) { throw '기대 테일넷이 없습니다. 맥북 CurrentTailnet.Name을 확인하고 -ExpectedTailnet으로 지정하세요.' }
        $expected = $ExpectedTailnet.Trim()
        $svc = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running') { Start-Service Tailscale; Start-Sleep -Seconds 3 }
        $ErrorActionPreference = 'Continue'
        $st = (& $t status --json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue)
        $ErrorActionPreference = 'Stop'
        if ($st.BackendState -eq 'Running') {
            $tailnet = [string]$st.CurrentTailnet.Name
            $ip = Get-NativeOutput $t @('ip','-4')
            if (-not $tailnet -or $tailnet -ine $expected) { throw "테일넷 불일치/확인 불가: 가입됨 테일넷=$tailnet IP=$ip 기대=$expected. 로그아웃/재가입은 자동 실행하지 않습니다." }
            if (-not $ip) { throw "가입됨 테일넷=$tailnet IP 확인 불가" }
            return "이미 가입됨 테일넷=$tailnet IP=$ip"
        }

        Write-Host '  Tailscale 사전 인증 키(tskey-auth-...)를 입력하세요. (화면에 표시되지 않음)'
        $sec = Read-Host '  인증 키' -AsSecureString
        if ($sec.Length -eq 0) { throw '인증 키가 비어 있습니다.' }
        # 키를 명령줄 인자/로그에 남기지 않기 위해 잠긴 임시 파일로 전달하고 즉시 삭제
        $keyFile = Join-Path $env:TEMP ("tsk-{0}.tmp" -f [guid]::NewGuid().ToString('N'))
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try {
            # 빈 파일에 ACL을 먼저 적용한 뒤 비밀값을 쓴다. 사용자 이름 대신 SID로 한글 계정도 처리.
            [System.IO.File]::WriteAllText($keyFile, '')
            $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            & icacls $keyFile /inheritance:r /grant:r "*$($sid):(F)" '*S-1-5-18:(R)' '*S-1-5-32-544:(R)' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw '인증 키 임시 파일 ACL 설정 실패' }
            [System.IO.File]::WriteAllText($keyFile, [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr), (New-Object System.Text.UTF8Encoding $false))
            $up = @('up', "--auth-key=file:$keyFile", '--unattended', '--accept-routes=false')
            if ($TsTag) { $up += "--advertise-tags=$TsTag" }
            $hn = if ($TsHostname) { $TsHostname } else { $env:COMPUTERNAME }
            $up += "--hostname=$hn"
            $ErrorActionPreference = 'Continue'   # PS 5.1: 네이티브 stderr 출력이 예외가 되지 않게
            & $t @up 2>&1 | Out-Host
            $ErrorActionPreference = 'Stop'
            if ($LASTEXITCODE -ne 0) { throw "tailscale up 실패 (종료코드 $LASTEXITCODE). 키 만료/재사용 불가/태그 권한을 확인하세요." }
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            Remove-Item -LiteralPath $keyFile -Force -ErrorAction SilentlyContinue
        }
        $ip = (Get-NativeOutput $t @('ip', '-4')) -split '\s+' | Select-Object -First 1
        if (-not $ip) { throw 'Tailscale IP 를 받지 못했습니다.' }
        $ErrorActionPreference = 'Continue'
        $st = (& $t status --json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue)
        $ErrorActionPreference = 'Stop'
        $tailnet = [string]$st.CurrentTailnet.Name
        if ($st.BackendState -ne 'Running' -or -not $tailnet -or $tailnet -ine $expected) { throw "가입 후 테일넷 불일치/확인 불가: 상태=$($st.BackendState) 테일넷=$tailnet IP=$ip 기대=$expected. 자동 재가입하지 않습니다." }
        "가입 완료 테일넷=$tailnet IP=$ip (관리 콘솔에서 이 기기 승인/태그 확인)"
    }
}

# 통로 단계 실패 시 녹화/앱 설치로 넘어가지 않는다.
if (($results | Where-Object { -not $_.Ok }).Count -gt 0) { Show-Summary; exit 1 }

# ---------------- 3. Git for Windows ----------------
if (-not $SkipGit) {
    Invoke-Step 'Git for Windows' {
        $g = & $GitExe
        if ($g) { return "이미 설치됨 ($g)" }
        Install-WithWinget 'Git.Git'
        if (-not (& $GitExe)) { throw 'Git 설치 후에도 git.exe 를 찾지 못했습니다.' }
        'git 설치 완료'
    }
}

# ---------------- 4. Claude Code (공식 네이티브 설치) ----------------
if (-not $SkipClaude) {
    Invoke-Step 'Claude Code' {
        $me = "$env:USERDOMAIN\$env:USERNAME"
        $ow = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName GetOwner } | Select-Object -First 1
        if ($ow -and $ow.User -and ("$($ow.Domain)\$($ow.User)" -ne $me)) {
            Write-Host "  주의: 이 PowerShell 계정($me)이 로그인 사용자($($ow.Domain)\$($ow.User))와 다릅니다. Claude Code 는 $me 프로필에 설치되어 고객 계정에서 안 보입니다." -ForegroundColor Yellow
            Write-Host '  -> 로그인 사용자 계정의 관리자 PowerShell 로 실행하거나, 이 단계만 고객 계정의 일반 PowerShell 에서 -SkipGit -SkipTailscale -SkipRecorder -SkipSsh 로 다시 실행하세요.' -ForegroundColor Yellow
        }
        $c = & $ClaudeExe
        if ($c) { return "이미 설치됨 ($(Get-NativeOutput $c @('--version')))" }
        Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
        $c = & $ClaudeExe
        if (-not $c) { throw 'claude.exe 를 찾지 못했습니다. 새 PowerShell 창에서 claude --version 을 확인하세요.' }
        $userBin = Split-Path $c
        $up = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($up -notlike "*$userBin*") { [Environment]::SetEnvironmentVariable('Path', "$up;$userBin", 'User') }
        "설치 완료 ($(Get-NativeOutput $c @('--version'))) - 로그인은 이 PC 에서 'claude' 실행 후 진행"
    }
}

# ---------------- 5. 화면 녹화 ----------------
if (-not $SkipRecorder) {
    Invoke-Step '화면 녹화' {
        $rec = Join-Path $here 'install-recorder.ps1'
        if (-not (Test-Path $rec)) { throw "install-recorder.ps1 을 찾지 못했습니다 ($rec)" }
        $params = @{ InstallDir = $InstallDir }
        if ($Customer) {
            $cf = Join-Path $here "customers\$Customer\config.json"
            if (-not (Test-Path $cf)) { throw "고객 설정이 없습니다: $cf" }
            $params.ConfigFile = $cf
        }
        & $rec @params | Out-Host
        "설치 위치 $InstallDir"
    }
}

Show-Summary
if (($results | Where-Object { -not $_.Ok }).Count -gt 0) { exit 1 }
