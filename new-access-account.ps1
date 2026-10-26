# AX Field Kit - 원격 통로 전용 일반 계정 만들기 (사람이 새 관리자 PowerShell 에서 직접 실행. Claude 는 대신 실행하지 않음)
# 계정은 Users 그룹에만 넣는다(Administrators 아님). 암호는 화면에 표시되지 않게 입력받고 인자·환경 변수·파일·로그에 남기지 않는다.
# 이미 있는 계정이면 만들거나 바꾸지 않고 그룹 소속·상태만 보고한다. 잠금 정책·LimitBlankPasswordUse 는 건드리지 않는다.
param(
    [Parameter(Mandatory = $true)]
    [string]$UserName                            # 전용 계정 이름 예: ops-remote (영문으로 시작, 영문·숫자·-·_ 20자 이내)
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
# uninstall.ps1 은 이 표식이 설명에 있는 계정만 삭제를 제안한다.
$Marker = 'Remote access (ax-field-kit)'
$SidAdmins = 'S-1-5-32-544'
$SidUsers = 'S-1-5-32-545'

function Get-GroupSids([string]$Name) {
    # Get-LocalGroupMember 는 고아 SID 가 있는 PC 에서 실패하므로 ADSI 로 계정의 그룹 SID 를 읽는다.
    $a = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,user"
    @($a.psbase.Invoke('Groups') | ForEach-Object {
        $b = $_.GetType().InvokeMember('objectSid', 'GetProperty', $null, $_, $null)
        (New-Object System.Security.Principal.SecurityIdentifier($b, 0)).Value
    })
}
function Show-Account([string]$Name) {
    $u = Get-LocalUser -Name $Name
    $g = Get-GroupSids $Name
    $locked = [bool]([ADSI]"WinNT://$env:COMPUTERNAME/$Name,user").psbase.InvokeGet('IsAccountLocked')
    Write-Host ("  계정={0} 사용={1} 잠김={2} 암호필수={3} Users={4} Administrators={5} 설명={6}" -f $Name, $u.Enabled, $locked, $u.PasswordRequired, ($g -contains $SidUsers), ($g -contains $SidAdmins), $u.Description)
    if ($g -contains $SidAdmins) { Write-Host '  경고: Administrators 소속입니다. 이 상태로는 sshd 가 계정의 개인 authorized_keys 를 읽지 않고 최소 권한도 아닙니다. 그룹 변경은 사람이 결정합니다.' -ForegroundColor Yellow }
    if (-not ($g -contains $SidUsers)) { Write-Host '  경고: Users 그룹 소속이 아닙니다.' -ForegroundColor Yellow }
    if ($u.Description -notlike "*$Marker*") { Write-Host '  참고: 이 스크립트가 만든 계정이 아니라 uninstall.ps1 이 자동 삭제를 제안하지 않습니다(회수 시 사람이 직접 삭제).' -ForegroundColor Yellow }
}
# 두 암호를 관리 문자열로 꺼내지 않고 비교한다.
function Test-SameSecret([Security.SecureString]$A, [Security.SecureString]$B) {
    if ($A.Length -ne $B.Length) { return $false }
    $pa = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($A)
    $pb = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($B)
    try {
        $same = $true
        for ($i = 0; $i -lt $A.Length; $i++) {
            if ([Runtime.InteropServices.Marshal]::ReadInt16($pa, $i * 2) -ne [Runtime.InteropServices.Marshal]::ReadInt16($pb, $i * 2)) { $same = $false }
        }
        return $same
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pa)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pb)
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host '관리자 권한이 아닙니다. 시작 메뉴에서 PowerShell 을 "관리자 권한으로 실행" 후 다시 하세요.' -ForegroundColor Red; exit 1 }
if ($UserName -cnotmatch '^[A-Za-z][A-Za-z0-9_-]{0,19}$') { Write-Host '계정 이름은 영문으로 시작하고 영문·숫자·-·_ 만, 20자 이내여야 합니다.' -ForegroundColor Red; exit 1 }
if ($UserName -ieq $env:USERNAME) { Write-Host '지금 로그인한 계정 이름입니다. 전용 계정은 새 이름으로 만드세요.' -ForegroundColor Red; exit 1 }

if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
    Write-Host "이미 있는 계정입니다. 만들거나 바꾸지 않고 상태만 보고합니다." -ForegroundColor Cyan
    Show-Account $UserName
    exit 0
}

Write-Host "전용 계정 $UserName 의 암호를 정하세요. (화면에 표시되지 않음, 어디에도 저장하지 않음)"
$p1 = Read-Host '  암호' -AsSecureString
$p2 = Read-Host '  암호 확인' -AsSecureString
if ($p1.Length -eq 0) { Write-Host '암호가 비어 있습니다. 빈 암호 계정은 만들지 않습니다.' -ForegroundColor Red; exit 1 }
if (-not (Test-SameSecret $p1 $p2)) { Write-Host '두 암호가 다릅니다. 다시 실행하세요.' -ForegroundColor Red; exit 1 }
$p2.Dispose()

try {
    New-LocalUser -Name $UserName -Password $p1 -Description $Marker -AccountNeverExpires | Out-Null
} finally { $p1.Dispose() }
# New-LocalUser 는 PasswordRequired=False 로 만들므로 암호 필수로 바꾼다(암호 값은 다루지 않음).
& net.exe user $UserName /passwordreq:yes | Out-Null
$pwReqOk = ($LASTEXITCODE -eq 0)
# New-LocalUser 는 어느 그룹에도 넣지 않으므로 Users 에만 넣는다.
Add-LocalGroupMember -SID $SidUsers -Member $UserName
Write-Host "만들었습니다." -ForegroundColor Green
Show-Account $UserName
if (-not $pwReqOk -or -not (Get-LocalUser -Name $UserName).PasswordRequired) {
    Write-Host "  경고: 암호 필수 설정이 되지 않았습니다. 이 관리자 PowerShell 에서 net user $UserName /passwordreq:yes 를 직접 실행한 뒤 다시 확인하세요." -ForegroundColor Red
    exit 1
}
Write-Host '다음: Claude 가 install.ps1 -SshUser 로 이 계정에 공개키를 등록합니다. 암호는 1Password 등 지정 보관 위치에 사람이 직접 보관하세요.'
