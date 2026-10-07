# AX Field Kit - 화면 녹화 런타임 (로그인 시 작업 스케줄러가 실행)
# 트레이 아이콘으로 항상 표시된다(빨강=녹화 중, 회색=대기/일시정지). 몰래 돌지 않는다.
# 동작: 업무 시간 + 화면 잠금 아님 + 자리 비움 아님 일 때만 ffmpeg(gdigrab)로 초당 1장 녹화,
#       활성 앱/창 이름을 JSONL로 기록, 오래된 파일 자동 삭제.
param([string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'))

$ErrorActionPreference = 'Stop'
# 숨은 창이라 시작 단계 오류가 안 보이므로 TEMP 에 남긴다
trap { try { Add-Content (Join-Path $env:TEMP 'AxFieldKit-recorder-crash.log') ("{0} {1}" -f (Get-Date), $_) } catch {}; break }

# ---- 단일 실행 보장 ----
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Global\AxFieldKitRecorder', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

# ---- 설정 ----
$cfg = Get-Content -Raw -Encoding UTF8 $ConfigPath | ConvertFrom-Json
function Cfg($name, $default) { if ($null -ne $cfg.$name) { $cfg.$name } else { $default } }
$DataDir       = Cfg 'dataDir' 'C:\AxFieldKit\data'
$Ffmpeg        = Cfg 'ffmpegPath' 'C:\AxFieldKit\bin\ffmpeg.exe'
$WorkStart     = [TimeSpan]::Parse((Cfg 'workStart' '09:00'))
$WorkEnd       = [TimeSpan]::Parse((Cfg 'workEnd' '18:00'))
$WorkDays      = @(Cfg 'workDays' @(1, 2, 3, 4, 5))   # 0=일 ... 6=토
$Fps           = [int](Cfg 'fps' 1)
$MaxWidth      = [int](Cfg 'maxWidth' 1600)
$Crf           = [int](Cfg 'crf' 32)
$SegmentSec    = [int](Cfg 'segmentSeconds' 300)
$RetentionDays = [int](Cfg 'retentionDays' 14)
$IdleSec       = [int](Cfg 'idleSeconds' 300)
$MinFreeGB     = [int](Cfg 'minFreeGB' 5)

$RecDir = Join-Path $DataDir 'recordings'
$LogDir = Join-Path $DataDir 'activity'
$SysLog = Join-Path $DataDir 'recorder.log'
# 고아 ffmpeg 정리: recorder 만 죽고 ffmpeg 가 남아 트레이 없이 녹화되는 것을 막는다
Get-CimInstance Win32_Process -Filter "Name='ffmpeg.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $Ffmpeg } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
foreach ($d in $DataDir, $RecDir, $LogDir) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

function Write-SysLog($msg) {
    try { Add-Content -Path $SysLog -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8 } catch {}
}

# ---- Win32 ----
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class AxNative {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
    public static uint IdleSeconds() {
        LASTINPUTINFO i = new LASTINPUTINFO(); i.cbSize = (uint)Marshal.SizeOf(i);
        if (!GetLastInputInfo(ref i)) return 0;
        return ((uint)Environment.TickCount - i.dwTime) / 1000;
    }
    // 화면 잠금/보안 데스크톱이면 입력 데스크톱을 열 수 없다
    public static bool IsLocked() {
        IntPtr d = OpenInputDesktop(0, false, 0x0100);
        if (d == IntPtr.Zero) return true;
        CloseDesktop(d); return false;
    }
}
'@
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function Get-ActiveWindow {
    $h = [AxNative]::GetForegroundWindow()
    if ($h -eq [IntPtr]::Zero) { return @{ app = ''; title = '' } }
    $sb = New-Object System.Text.StringBuilder 512
    [void][AxNative]::GetWindowText($h, $sb, 512)
    $procId = [uint32]0
    [void][AxNative]::GetWindowThreadProcessId($h, [ref]$procId)
    $app = ''
    try { $app = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch {}
    return @{ app = $app; title = $sb.ToString() }
}

# ---- 트레이 ----
function New-DotIcon([System.Drawing.Color]$color) {
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush $color), 1, 1, 14, 14)
    $g.Dispose()
    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon).Clone()
    [void][AxNative]::DestroyIcon($hIcon)
    $bmp.Dispose()
    return $icon
}
$iconRec  = New-DotIcon ([System.Drawing.Color]::Red)
$iconIdle = New-DotIcon ([System.Drawing.Color]::Gray)

$script:paused = $false
$script:proc = $null
$script:lastKey = ''
$script:lastWrite = [DateTime]::MinValue
$script:lastClean = [DateTime]::MinValue
$script:fastFails = 0
$script:state = ''

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $iconIdle
$tray.Text = 'AX 화면 녹화 - 대기'
$tray.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miInfo  = $menu.Items.Add(("업무 시간 {0:hh\:mm}~{1:hh\:mm} 에만 녹화합니다" -f $WorkStart, $WorkEnd)); $miInfo.Enabled = $false
$miPause = $menu.Items.Add('일시정지')
$miOpen  = $menu.Items.Add('저장 폴더 열기')
$miQuit  = $menu.Items.Add('녹화 종료 (이번 로그인만)')
$tray.ContextMenuStrip = $menu
$miPause.add_Click({
    $script:paused = -not $script:paused
    $miPause.Text = if ($script:paused) { '재개' } else { '일시정지' }
})
$miOpen.add_Click({ Start-Process explorer.exe $DataDir })
$miQuit.add_Click({ [System.Windows.Forms.Application]::Exit() })

# ---- 녹화 제어 ----
function Start-Rec {
    if ($script:proc -and -not $script:proc.HasExited) { return }
    $out = Join-Path $RecDir 'rec_%Y%m%d_%H%M%S.mkv'
    $ffArgs = @(
        '-hide_banner', '-loglevel', 'error', '-nostats', '-y',
        '-f', 'gdigrab', '-framerate', "$Fps", '-draw_mouse', '1', '-i', 'desktop',
        '-vf', "scale='min($MaxWidth,iw)':-2",
        '-c:v', 'libx264', '-preset', 'veryfast', '-crf', "$Crf", '-pix_fmt', 'yuv420p', '-g', '10',
        '-f', 'segment', '-segment_time', "$SegmentSec", '-reset_timestamps', '1', '-strftime', '1',
        ('"{0}"' -f $out)
    )
    $started = Get-Date
    $script:proc = Start-Process -FilePath $Ffmpeg -ArgumentList $ffArgs -WindowStyle Hidden -PassThru `
        -RedirectStandardError (Join-Path $DataDir 'ffmpeg-error.log')
    $script:procStarted = $started
    Write-SysLog "ffmpeg 시작 pid=$($script:proc.Id)"
}
function Stop-Rec {
    if ($script:proc -and -not $script:proc.HasExited) {
        try { $script:proc.Kill() } catch {}
        Write-SysLog 'ffmpeg 중지'
    }
    $script:proc = $null
}

function Test-ShouldRecord {
    if ($script:paused) { return 'paused' }
    $now = Get-Date
    if ($WorkDays -notcontains [int]$now.DayOfWeek) { return 'offday' }
    if ($now.TimeOfDay -lt $WorkStart -or $now.TimeOfDay -ge $WorkEnd) { return 'offhours' }
    if ([AxNative]::IsLocked()) { return 'locked' }
    if ([AxNative]::IdleSeconds() -ge $IdleSec) { return 'idle' }
    $drive = (Split-Path -Qualifier $DataDir).TrimEnd(':')
    $free = (Get-PSDrive -Name $drive -ErrorAction SilentlyContinue).Free
    if ($free -and ($free / 1GB) -lt $MinFreeGB) { return 'lowdisk' }
    return 'record'
}

function Write-Activity($reason) {
    $w = Get-ActiveWindow
    $key = "$($w.app)|$($w.title)"
    $now = Get-Date
    if ($key -eq $script:lastKey -and ($now - $script:lastWrite).TotalSeconds -lt 30) { return }
    $script:lastKey = $key; $script:lastWrite = $now
    $line = (@{ ts = $now.ToString('yyyy-MM-ddTHH:mm:sszzz'); app = $w.app; title = $w.title; event = $reason } | ConvertTo-Json -Compress)
    $file = Join-Path $LogDir ($now.ToString('yyyy-MM-dd') + '.jsonl')
    [System.IO.File]::AppendAllText($file, $line + "`n", (New-Object System.Text.UTF8Encoding $false))
}

function Remove-Old {
    $limit = (Get-Date).AddDays(-$RetentionDays)
    foreach ($d in $RecDir, $LogDir) {
        Get-ChildItem $d -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $limit } |
            ForEach-Object { try { Remove-Item $_.FullName -Force } catch {} }
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.add_Tick({
    try {
        $s = Test-ShouldRecord
        if ($s -eq 'record') {
            if ($script:proc -and $script:proc.HasExited) {
                if (((Get-Date) - $script:procStarted).TotalSeconds -lt 20) { $script:fastFails++ } else { $script:fastFails = 0 }
                Write-SysLog "ffmpeg 종료됨 code=$($script:proc.ExitCode) (연속 빠른 실패 $($script:fastFails)) - ffmpeg-error.log 확인"
                $script:proc = $null
            }
            if ($script:fastFails -lt 5) { Start-Rec }
            elseif ($script:fastFails -eq 5) { $script:fastFails++; $tray.ShowBalloonTip(8000, 'AX 화면 녹화', '녹화 시작에 계속 실패합니다. 담당자에게 알려 주세요.', 'Error') }
            Write-Activity 'tick'
        } else {
            Stop-Rec
            $script:fastFails = 0
        }
        if ($s -ne $script:state) {
            $script:state = $s
            if ($s -eq 'record') { $tray.Icon = $iconRec;  $tray.Text = 'AX 화면 녹화 - 녹화 중' }
            else                 { $tray.Icon = $iconIdle; $tray.Text = "AX 화면 녹화 - 대기 ($s)" }
            Write-SysLog "상태 -> $s"
            if ($s -eq 'record') { $tray.ShowBalloonTip(4000, 'AX 화면 녹화', '업무 화면 녹화가 시작되었습니다. 트레이 아이콘에서 일시정지할 수 있습니다.', 'Info') }
        }
        if (((Get-Date) - $script:lastClean).TotalMinutes -ge 10) { $script:lastClean = Get-Date; Remove-Old }
    } catch { Write-SysLog "오류: $($_.Exception.Message)" }
})
$timer.Start()

Write-SysLog "recorder 시작 (업무 $WorkStart~$WorkEnd, ${Fps}fps, 보관 ${RetentionDays}일)"
try { [System.Windows.Forms.Application]::Run() }
finally {
    $timer.Stop(); Stop-Rec
    $tray.Visible = $false; $tray.Dispose()
    Write-SysLog 'recorder 종료'
    $mutex.ReleaseMutex()
}
