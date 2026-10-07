# AX Field Kit - 동작 확인 (일반 PowerShell 가능)
param([string]$InstallDir = 'C:\AxFieldKit')
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$fail = 0
function Row($ok, $name, $detail) {
    if ($ok) { Write-Host ("[OK]   {0}  {1}" -f $name, $detail) -ForegroundColor Green }
    else { Write-Host ("[실패] {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
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
    Row ($st.BackendState -eq 'Running' -and $ip) 'Tailscale' "상태=$($st.BackendState) IP=$ip"
} else { Row $false 'Tailscale' 'tailscale.exe 없음' }

# 녹화
$task = Get-ScheduledTask -TaskName 'AxFieldKitRecorder' -ErrorAction SilentlyContinue
Row ($null -ne $task) '자동 시작 작업' $(if ($task) { "상태=$($task.State)" } else { '미등록' })
$rp = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'recorder\.ps1' }
Row ($null -ne $rp) '녹화 프로그램' $(if ($rp) { "pid=$($rp[0].ProcessId)" } else { '실행 중 아님' })
$ff = Get-Process ffmpeg -ErrorAction SilentlyContinue
Write-Host ("       ffmpeg: {0}" -f $(if ($ff) { '녹화 중' } else { '대기 (업무 시간 밖/잠금/자리 비움이면 정상)' }))
$rec = Join-Path $InstallDir 'data\recordings'
$last = Get-ChildItem $rec -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($last) {
    $ageMin = [math]::Round(((Get-Date) - $last.LastWriteTime).TotalMinutes, 1)
    Write-Host ("       최근 파일: {0} ({1} MB, {2}분 전)" -f $last.Name, [math]::Round($last.Length / 1MB, 2), $ageMin)
} else { Write-Host '       녹화 파일 아직 없음 (업무 시간 안에서 몇 분 기다린 뒤 다시 확인)' }
$act = Get-ChildItem (Join-Path $InstallDir 'data\activity') -Filter *.jsonl -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($act) { Write-Host "       활동 기록 마지막 줄: $((Get-Content $act.FullName -Tail 1 -Encoding UTF8))" }
$log = Join-Path $InstallDir 'data\recorder.log'
if (Test-Path $log) { Write-Host '       recorder.log 최근:'; Get-Content $log -Tail 3 -Encoding UTF8 | ForEach-Object { Write-Host "         $_" } }
$e = Join-Path $InstallDir 'data\ffmpeg-error.log'
if ((Test-Path $e) -and (Get-Item $e).Length -gt 0) { Write-Host '       ffmpeg-error.log:' -ForegroundColor Yellow; Get-Content $e -Tail 3 | ForEach-Object { Write-Host "         $_" } }

Write-Host ''
if ($fail -eq 0) { Write-Host '모두 정상' -ForegroundColor Green } else { Write-Host "$fail 개 항목 확인 필요" -ForegroundColor Red; exit 1 }
