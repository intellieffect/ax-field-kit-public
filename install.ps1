# AX Field Kit - 현장 설치 진입점 (Windows 10/11, 관리자 PowerShell)
# Git for Windows -> Claude Code -> Tailscale(가입) -> 화면 녹화. 다시 실행해도 안전(이미 있으면 건너뜀).
param(
    [string]$Customer = '',                      # customers\<이름>\config.json 사용
    [string]$TsTag = '',                         # Tailscale 태그 예: tag:field (키에 태그 권한 필요)
    [string]$TsHostname = '',                    # Tailscale 기기 이름 (기본: 컴퓨터 이름)
    [string]$InstallDir = 'C:\AxFieldKit',
    [switch]$SkipGit,
    [switch]$SkipClaude,
    [switch]$SkipTailscale,
    [switch]$SkipRecorder,
    [switch]$SkipSsh,                            # OpenSSH 서버 설치 건너뜀 (기본은 켬: Tailscale 대역에서만 허용, 파일 회수 경로)
    [string]$SshPublicKey = '',                  # 우리 쪽 SSH 공개키 한 줄 (공개키라 비밀 아님) -> administrators_authorized_keys
    [switch]$EnableSsh,                          # (구 옵션, 이제 기본값이라 무시)
    [switch]$ContinueOnError                     # 단계 실패 시 묻지 않고 다음 단계로
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
        if (-not $ContinueOnError) {
            $a = Read-Host '  다음 단계로 계속할까요? (y=계속 / 그 외=중단)'
            if ($a -notmatch '^[yY]') { Show-Summary; exit 1 }
        }
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
    Write-Host '확인:  powershell -ExecutionPolicy Bypass -File .\check.ps1' -ForegroundColor Cyan
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

# ---------------- 1. Git for Windows ----------------
if (-not $SkipGit) {
    Invoke-Step 'Git for Windows' {
        $g = & $GitExe
        if ($g) { return "이미 설치됨 ($g)" }
        Install-WithWinget 'Git.Git'
        if (-not (& $GitExe)) { throw 'Git 설치 후에도 git.exe 를 찾지 못했습니다.' }
        'git 설치 완료'
    }
}

# ---------------- 2. Claude Code (공식 네이티브 설치) ----------------
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

# ---------------- 3. Tailscale ----------------
if (-not $SkipTailscale) {
    Invoke-Step 'Tailscale 설치' {
        $t = & $TailscaleExe
        if ($t) { return "이미 설치됨 ($t)" }
        try { Install-WithWinget 'Tailscale.Tailscale' }
        catch {
            Write-Host "  winget 실패, MSI 직접 설치 시도: $($_.Exception.Message)" -ForegroundColor Yellow
            $msi = Join-Path $env:TEMP 'tailscale-setup.msi'
            Invoke-WebRequest 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' -OutFile $msi -UseBasicParsing
            $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait -PassThru
            if ($p.ExitCode -notin 0, 3010) { throw "Tailscale MSI 설치 실패 (종료코드 $($p.ExitCode))" }
        }
        if (-not (& $TailscaleExe)) { throw 'Tailscale 설치 후 tailscale.exe 를 찾지 못했습니다.' }
        '설치 완료'
    }
    Invoke-Step 'Tailscale 가입' {
        $t = & $TailscaleExe
        if (-not $t) { throw 'tailscale.exe 없음 (이전 단계 실패)' }
        $svc = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running') { Start-Service Tailscale; Start-Sleep -Seconds 3 }
        $ErrorActionPreference = 'Continue'
        $state = (& $t status --json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue).BackendState
        $ErrorActionPreference = 'Stop'
        if ($state -eq 'Running') { return "이미 가입됨 ($(Get-NativeOutput $t @('ip','-4')))" }

        Write-Host '  Tailscale 사전 인증 키(tskey-auth-...)를 입력하세요. (화면에 표시되지 않음)'
        $sec = Read-Host '  인증 키' -AsSecureString
        if ($sec.Length -eq 0) { throw '인증 키가 비어 있습니다.' }
        # 키를 명령줄 인자/로그에 남기지 않기 위해 잠긴 임시 파일로 전달하고 즉시 삭제
        $keyFile = Join-Path $env:TEMP ("tsk-{0}.tmp" -f [guid]::NewGuid().ToString('N'))
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try {
            [System.IO.File]::WriteAllText($keyFile, [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr), (New-Object System.Text.UTF8Encoding $false))
            & icacls $keyFile /inheritance:r /grant:r "$($env:USERNAME):(R)" "*S-1-5-18:(R)" "*S-1-5-32-544:(R)" | Out-Null
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
            Remove-Item $keyFile -Force -ErrorAction SilentlyContinue
        }
        $ip = (Get-NativeOutput $t @('ip', '-4')) -split '\s+' | Select-Object -First 1
        if (-not $ip) { throw 'Tailscale IP 를 받지 못했습니다.' }
        "가입 완료, IP $ip (관리 콘솔에서 이 기기 승인/태그 확인)"
    }
}

# ---------------- 4. SSH (선택) ----------------
if (-not $SkipSsh) {
    Invoke-Step 'OpenSSH 서버 (Tailscale 대역 전용)' {
        $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
        if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
        Set-Service -Name sshd -StartupType Automatic
        Start-Service sshd
        Get-NetFirewallRule -Name 'AxFieldKit-SSH' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        # 기본 sshd 규칙은 전체 허용이므로 끄고, Tailscale 대역(100.64.0.0/10)만 허용
        Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
        New-NetFirewallRule -Name 'AxFieldKit-SSH' -DisplayName 'AX Field Kit SSH (Tailscale only)' -Direction Inbound `
            -Protocol TCP -LocalPort 22 -RemoteAddress '100.64.0.0/10' -Action Allow | Out-Null
        if ($SshPublicKey) {
            $ak = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
            # 줄 끝의 ax-field-kit 표식으로 uninstall 이 이 줄만 제거
            $already = (Test-Path $ak) -and (Select-String -Path $ak -SimpleMatch -Pattern $SshPublicKey -Quiet)
            if (-not $already) { Add-Content -Path $ak -Value ($SshPublicKey.Trim() + ' ax-field-kit') -Encoding ascii }
            & icacls $ak /inheritance:r /grant '*S-1-5-32-544:F' '*S-1-5-18:F' | Out-Null
        }
        'sshd 켜짐 (100.64.0.0/10 에서만 접속 가능)' + $(if ($SshPublicKey) { ', 공개키 등록' } else { ' - 공개키 미등록: 계정 비밀번호로 접속(-SshPublicKey 권장)' })
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
