# AX Field Kit - 철수 (관리자 PowerShell). 고객 데이터는 묻지 않고 지우지 않는다.
param(
    [string]$InstallDir = 'C:\AxFieldKit',
    [switch]$KeepData,        # 녹화 파일 보존 (묻지 않음)
    [switch]$DeleteData,      # 녹화 파일 삭제 (묻지 않음)
    [switch]$KeepSsh          # sshd 와 우리 공개키를 남김 (기본은 정리)
)
$ErrorActionPreference = 'Continue'
function Step($m) { Write-Host "== $m" -ForegroundColor Cyan }

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

Step 'OpenSSH 정리'
if ($KeepSsh) { Write-Host '  -KeepSsh: sshd 와 공개키를 그대로 둡니다.' }
else {
    Get-NetFirewallRule -Name 'AxFieldKit-SSH' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    $ak = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    if (Test-Path $ak) {
        $keep = @(Get-Content $ak | Where-Object { $_ -and $_ -notmatch 'ax-field-kit\s*$' })
        if ($keep.Count -eq 0) { Remove-Item $ak -Force } else { Set-Content $ak $keep -Encoding ascii }
        Write-Host '  우리 공개키 줄을 제거했습니다.'
    }
    if (Get-Service sshd -ErrorAction SilentlyContinue) {
        Stop-Service sshd -ErrorAction SilentlyContinue; Set-Service sshd -StartupType Disabled
        Write-Host '  sshd 중지 + 사용 안 함 (고객이 이전부터 쓰던 SSH 였다면 -KeepSsh 로 다시 실행)'
    }
}

Step 'Tailscale 로그아웃'
$t = (Get-Command tailscale.exe -ErrorAction SilentlyContinue).Source
if (-not $t -and (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) { $t = "$env:ProgramFiles\Tailscale\tailscale.exe" }
if ($t) { $ErrorActionPreference = 'Continue'; & $t logout 2>&1 | Out-Host; Write-Host '  (기기 삭제는 Tailscale 관리 콘솔에서도 확인)' } else { Write-Host '  Tailscale 없음 - 건너뜀' }

Step 'Claude Code 로그아웃 안내'
Write-Host '  이 PC 에서 claude 를 실행해 /logout 하세요. (프로그램 자체 제거: Remove-Item $env:USERPROFILE\.local\bin\claude.exe, $env:USERPROFILE\.local\share\claude)'
Write-Host ''
Write-Host '철수 완료. Tailscale/Git 프로그램 자체는 남겨 둡니다(필요 시 설정 > 앱에서 제거).' -ForegroundColor Green
