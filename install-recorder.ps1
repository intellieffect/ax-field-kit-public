# AX Field Kit - 녹화 설치 (ffmpeg + recorder.ps1 + 로그인 시 자동 시작)
# 단독 실행 가능. install.ps1 이 호출한다. 관리자 PowerShell 에서 실행.
param(
    [string]$InstallDir = 'C:\AxFieldKit',
    [string]$ConfigFile,                 # 예: customers\<고객>\config.json (없으면 기본값)
    [string]$TaskUser                    # 녹화 대상 Windows 사용자 (기본: 지금 로그인해 있는 사용자)
)
$ErrorActionPreference = 'Stop'
$TaskName = 'AxFieldKitRecorder'
$here = $PSScriptRoot

function Say($m) { Write-Host "  $m" }

# 1) 폴더
$bin = Join-Path $InstallDir 'bin'
$data = Join-Path $InstallDir 'data'
foreach ($d in $InstallDir, $bin, $data) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
# 일반 사용자도 data 에 쓸 수 있어야 한다(녹화 프로세스는 로그인 사용자 권한)
& icacls $data /grant '*S-1-5-32-545:(OI)(CI)M' /T /C | Out-Null

# 2) ffmpeg
$ffmpegDest = Join-Path $bin 'ffmpeg.exe'
if (Test-Path $ffmpegDest) {
    Say 'ffmpeg 이미 있음 - 건너뜀'
} else {
    $found = (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue).Source
    if (-not $found) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget 이 없습니다. ffmpeg.exe 를 직접 $bin 에 복사한 뒤 다시 실행하세요." }
        Say 'ffmpeg 설치 중 (winget Gyan.FFmpeg)...'
        & winget install --id Gyan.FFmpeg -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
        $found = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages", "$env:ProgramFiles\WinGet\Packages", "$env:ProgramData\chocolatey\bin" `
            -Filter ffmpeg.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if (-not $found) { $found = (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue).Source }
    }
    if (-not $found) { throw "ffmpeg.exe 를 찾지 못했습니다. 직접 $bin 에 복사한 뒤 다시 실행하세요." }
    Copy-Item $found $ffmpegDest -Force
    Say "ffmpeg 복사: $ffmpegDest"
}
$ErrorActionPreference = 'Continue'
& $ffmpegDest -hide_banner -version 2>&1 | Select-Object -First 1 | ForEach-Object { Say "$_" }
$ErrorActionPreference = 'Stop'

# 3) 스크립트 + 설정
Copy-Item (Join-Path $here 'recorder.ps1') (Join-Path $InstallDir 'recorder.ps1') -Force
$cfgDest = Join-Path $InstallDir 'config.json'
if ($ConfigFile) {
    if (-not (Test-Path $ConfigFile)) { throw "설정 파일이 없습니다: $ConfigFile" }
    Copy-Item $ConfigFile $cfgDest -Force
} elseif (-not (Test-Path $cfgDest)) {
    Copy-Item (Join-Path $here 'customers\_example\config.json') $cfgDest -Force
}
# 경로 값은 설치 위치 기준으로 항상 덮어쓴다
$cfg = Get-Content -Raw -Encoding UTF8 $cfgDest | ConvertFrom-Json
$cfg | Add-Member -NotePropertyName dataDir -NotePropertyValue $data -Force
$cfg | Add-Member -NotePropertyName ffmpegPath -NotePropertyValue $ffmpegDest -Force
[System.IO.File]::WriteAllText($cfgDest, ($cfg | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))
Say "설정: $cfgDest (업무시간 $($cfg.workStart)~$($cfg.workEnd), 보관 $($cfg.retentionDays)일)"

# 4) 작업 스케줄러: 로그인 시 자동 시작 (대상 사용자 권한, 숨김 창, 트레이는 config showTray 기본 숨김)
if (-not $TaskUser) {
    $owner = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName GetOwner } | Select-Object -First 1
    if ($owner -and $owner.User) { $TaskUser = "$($owner.Domain)\$($owner.User)" } else { $TaskUser = "$env:USERDOMAIN\$env:USERNAME" }
}
Say "녹화 대상 사용자: $TaskUser"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -ConfigPath "{1}"' -f (Join-Path $InstallDir 'recorder.ps1'), $cfgDest)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $TaskUser
$principal = New-ScheduledTaskPrincipal -UserId $TaskUser -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description 'AX Field Kit 화면 녹화 (업무 시간만)' -Force | Out-Null
Say "작업 스케줄러 등록: $TaskName"

# 5) 지금 바로 시작
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 4
$running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'recorder\.ps1' }
if ($running) { Say '녹화 프로그램 실행 중 (트레이는 기본 숨김 - 녹화 여부는 data\recordings 의 새 파일로 확인)' }
else { throw "녹화 프로그램이 시작되지 않았습니다. $data\recorder.log 와 작업 스케줄러 '$TaskName' 를 확인하세요. 시작 단계 오류는 $env:TEMP\AxFieldKit-recorder-crash.log (녹화 대상 사용자의 TEMP)에도 남습니다." }

Write-Host "  데이터 처리: 저장 위치 $data, 보관 $($cfg.retentionDays)일 후 자동 삭제, 열람은 담당자(Tailscale)만." -ForegroundColor DarkGray
