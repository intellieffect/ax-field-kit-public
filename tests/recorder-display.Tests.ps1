# Runs on macOS/Windows PowerShell without recording, opening a window, or registering OS notifications.
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'recorder.ps1'
$source = [IO.File]::ReadAllText($sourcePath)
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$native = [regex]::Match($source, "(?s)Add-Type @'\r?\n(.*?)\r?\n'@").Groups[1].Value
if (-not $native) { throw 'Native source not found' }
Add-Type -TypeDefinition $native
$function = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-ShouldRecord'
}, $true)
. ([scriptblock]::Create($function.Extent.Text))

$script:checks = 0
function Assert-Equal($actual, $expected, $label) {
    if ($actual -cne $expected) { throw "$label expected '$expected', got '$actual'" }
    $script:checks++
}
$callback = [AxNative].GetMethod('OnDisplayPower', [Reflection.BindingFlags]'NonPublic,Static')
$displayGuid = [guid]'2b84c20e-ad23-4ddf-93db-05ffbd7efca5'
$buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal(24)
function Send-DisplayValue([int]$value, [int]$length = 4, [guid]$id = $displayGuid, [uint32]$type = 0x8013) {
    [Runtime.InteropServices.Marshal]::StructureToPtr($id, $buffer, $false)
    [Runtime.InteropServices.Marshal]::WriteInt32($buffer, 16, $length)
    [Runtime.InteropServices.Marshal]::WriteInt32($buffer, 20, $value)
    $result = $callback.Invoke($null, @([IntPtr]::Zero, $type, $buffer))
    Assert-Equal $result ([uint32]0) 'callback result'
}

# No Windows calls should be reached while off/unknown; on/dim must still obey workdays.
$script:paused = $false
$WorkDays = @()
try {
    Assert-Equal ([AxNative]::DisplayPauseReason()) 'display_unknown' 'initial state'
    Assert-Equal (Test-ShouldRecord) 'display_unknown' 'startup fails closed'
    Send-DisplayValue 1
    Assert-Equal ([AxNative]::DisplayPauseReason()) '' 'on allowed'
    Assert-Equal (Test-ShouldRecord) 'offday' 'on preserves schedule gate'
    Send-DisplayValue 0
    Assert-Equal (Test-ShouldRecord) 'display_off' 'on to off blocks recording'
    Send-DisplayValue 1
    Assert-Equal (Test-ShouldRecord) 'offday' 'off to on reevaluates other gates'
    Send-DisplayValue 2
    Assert-Equal ([AxNative]::DisplayPauseReason()) '' 'dimmed remains visible'
    Assert-Equal (Test-ShouldRecord) 'offday' 'dim preserves schedule gate'
    Send-DisplayValue 0 4 ([guid]::Empty)
    Assert-Equal ([AxNative]::DisplayPauseReason()) '' 'unrelated setting ignored'
    Send-DisplayValue 0 4 $displayGuid 0x12
    Assert-Equal ([AxNative]::DisplayPauseReason()) '' 'unrelated event ignored'
    Send-DisplayValue 1 0
    Assert-Equal (Test-ShouldRecord) 'display_unknown' 'empty payload fails closed'
    Send-DisplayValue 1 8
    Assert-Equal (Test-ShouldRecord) 'display_unknown' 'wrong payload length fails closed'
    Send-DisplayValue 3
    Assert-Equal (Test-ShouldRecord) 'display_unknown' 'unknown enum fails closed'
    Send-DisplayValue -1
    Assert-Equal (Test-ShouldRecord) 'display_unknown' 'invalid enum fails closed'
    Send-DisplayValue 1
    [void]$callback.Invoke($null, @([IntPtr]::Zero, [uint32]0x8013, [IntPtr]::Zero))
    Assert-Equal (Test-ShouldRecord) 'display_unknown' 'null payload fails closed'
    $script:paused = $true
    Assert-Equal (Test-ShouldRecord) 'paused' 'manual pause preserved'
    $script:paused = $false
    Send-DisplayValue 1
    [AxNative]::StopDisplayNotifications()
    Assert-Equal (Test-ShouldRecord) 'display_unknown' 'cleanup resets readiness'
    Write-Output "PASS: $script:checks assertions; native callback and actual recording gate; no OS display changes"
} finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
}
