# AX Field Kit - sshd 공용 함수 (install.ps1·check.ps1·uninstall.ps1 이 dot-source 한다. 혼자 실행하면 함수만 정의하고 끝남)
# 전용 계정만 비밀번호 SSH 끄기의 표식 블록과, 시간 제한을 건 sshd 실행.
# sshd -T -C user=<계정> 는 쓰지 않는다: 기본 sshd_config 의 'Match Group administrators' 때문에 그룹을 풀어야 하는데
# SYSTEM 이 아닌 관리자에서는 'ga_init, unable to resolve user' 로 실패하고 & 호출에서는 끝나지 않고 멈췄다(리허설).
# 그래서 sshd_config 를 읽어 정적으로 검증하고, 실제 거부는 맥에서 비밀번호 SSH 를 시도해 확인한다(docs/원격-통로.md 6절).
$SshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
$SshdExe = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'

function Get-SshdBlockBegin([string]$User) { "# BEGIN ax-field-kit access-account $User (uninstall.ps1 removes this block)" }
function Get-SshdBlockEnd([string]$User) { "# END ax-field-kit access-account $User" }

function Invoke-NativeTimed([string]$Exe, [string]$Arguments, [int]$TimeoutMs = 15000) {
    # 외부 프로그램을 시간 제한을 두고 실행한다. stdin 은 빈 파일, stdout/stderr 는 임시 파일. 넘으면 강제 종료.
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ('axfk-' + [guid]::NewGuid().ToString('N'))
    $in = "$base.in"; $out = "$base.out"; $err = "$base.err"
    [System.IO.File]::WriteAllText($in, '')
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err
        $null = $p.Handle   # 핸들을 먼저 잡아야 PS 5.1 에서 ExitCode 가 비지 않는다(진단)
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch {}
            return [pscustomobject]@{ TimedOut = $true; ExitCode = $null; Out = ''; Err = '' }
        }
        $p.WaitForExit()
        $o = if (Test-Path -LiteralPath $out) { [System.IO.File]::ReadAllText($out) } else { '' }
        $e = if (Test-Path -LiteralPath $err) { [System.IO.File]::ReadAllText($err) } else { '' }
        [pscustomobject]@{ TimedOut = $false; ExitCode = $p.ExitCode; Out = $o.Trim(); Err = $e.Trim() }
    } finally { Remove-Item -LiteralPath $in, $out, $err -Force -ErrorAction SilentlyContinue }
}

function Test-SshdConfig {
    # sshd -t: 문법 검사(15초 제한). Ok 와 오류 문구를 돌려준다.
    $r = Invoke-NativeTimed $SshdExe '-t' 15000
    if ($r.TimedOut) { return [pscustomobject]@{ Ok = $false; Text = 'sshd -t 가 15초 안에 끝나지 않아 강제 종료' } }
    [pscustomobject]@{ Ok = ($r.ExitCode -eq 0); Text = ("$($r.Err) $($r.Out)").Trim() }
}

function Read-SshdConfigText([string]$Path) {
    # UTF-16 이면 sshd 도 우리 코드도 제대로 못 읽으므로 throw. BOM 은 떼고 돌려준다.
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if (($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) -or ($bytes -contains [byte]0)) { throw "$Path 가 UTF-16 입니다. 자동으로 고치지 않습니다 - 사람이 확인하세요." }
    [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
}

function Get-LocalGroupNames([string]$User) {
    # 계정이 속한 로컬 그룹 이름(ADSI). 모든 계정에 붙는 Everyone·Authenticated Users 도 넣는다(Match Group 판단을 보수적으로).
    $a = [ADSI]"WinNT://$env:COMPUTERNAME/$User,user"
    @($a.psbase.Invoke('Groups') | ForEach-Object { [string]$_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null) }) + @('Everyone', 'Authenticated Users')
}

function Test-SshPatternList([string]$Value, [string]$List) {
    # OpenSSH 패턴 목록(쉼표, * ?, ! 부정). 1 = 맞음, -1 = 부정에 걸림, 0 = 안 맞음. Windows 라 대소문자 무시.
    $hit = 0
    foreach ($p in ($List -split ',')) {
        $p = $p.Trim(); if (-not $p) { continue }
        $neg = $p.StartsWith('!'); if ($neg) { $p = $p.Substring(1) }
        $rx = '^' + ([regex]::Escape($p) -replace '\\\*', '.*' -replace '\\\?', '.') + '$'
        if ($Value -imatch $rx) { if ($neg) { return -1 }; $hit = 1 }
    }
    $hit
}

function Test-SshdMatchMayApply([string]$Criteria, [string]$User, [string[]]$Groups) {
    # Match 줄의 조건이 이 계정 접속에 적용될 수 있으면 $true. 조건은 모두 맞아야 적용되므로 확실히 안 맞는 조건이 하나라도 있으면 $false.
    # Host·Address·LocalPort 등 접속마다 다른 조건은 '적용될 수 있음'으로 본다.
    $tok = @([regex]::Matches($Criteria, '"[^"]*"|[^\s"]+') | ForEach-Object { $_.Value.Trim('"') })
    for ($i = 0; $i -lt $tok.Count; $i++) {
        $k = $tok[$i].ToLowerInvariant()
        if ($k -eq 'all') { continue }
        if ($k -eq 'invalid-user') { return $false }   # 전용 계정은 있는 계정
        $v = if ($i + 1 -lt $tok.Count) { $tok[$i + 1] } else { '' }; $i++
        if ($k -eq 'user' -and (Test-SshPatternList $User $v) -ne 1) { return $false }
        if ($k -eq 'group') {
            $r = @($Groups | ForEach-Object { Test-SshPatternList $_ $v })
            if ($r -contains -1 -or $r -notcontains 1) { return $false }
        }
    }
    $true
}

function Test-AccessAccountKeyOnly([string]$Text, [string]$User, [string[]]$Groups) {
    # sshd_config 정적 검증. 반환 Ok/Reason.
    # (a) 우리 표식 블록이 정확히 1개, 블록 뒤에는 빈 줄·주석 또는 Match 줄로 시작하는 블록만(다른 전용 계정 블록 포함), 안은 'Match User <계정>' + 'PasswordAuthentication no'
    # (b) 그보다 앞서 이 계정에 적용될 수 있는 Match 블록에 PasswordAuthentication(no 아님)이 없음
    # sshd 는 같은 키워드의 처음 얻은 값을 쓰고(sshd_config(5) "the first obtained value will be used"), 접속 때 맞는 Match 블록의 값이 전역 값을 덮는다.
    $u = $User.ToLowerInvariant()
    $lines = @($Text.TrimStart([char]0xFEFF) -split "`r?`n")
    $begin = Get-SshdBlockBegin $u; $end = Get-SshdBlockEnd $u
    $bi = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -ceq $begin) { $i } })
    $ei = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -ceq $end) { $i } })
    $fail = { param($m) [pscustomobject]@{ Ok = $false; Reason = $m } }
    if ($bi.Count -ne 1 -or $ei.Count -ne 1) { return (& $fail "표식 블록 BEGIN $($bi.Count)개·END $($ei.Count)개 (정확히 1개씩이어야 함)") }
    $b = $bi[0]; $e = $ei[0]
    if ($e -le $b + 1) { return (& $fail '표식 블록 END 가 BEGIN 앞이거나 블록이 비어 있음') }
    $isSetting = { param($l) $t = $l.Trim(); $t -and -not $t.StartsWith('#') }
    $norm = { param($l) (($l.Trim() -split '[\s=]+') -join ' ').ToLowerInvariant() }
    $body = @($lines[($b + 1)..($e - 1)] | Where-Object { & $isSetting $_ } | ForEach-Object { & $norm $_ })
    if ($body.Count -ne 2 -or $body[0] -cne "match user $u" -or $body[1] -cne 'passwordauthentication no') { return (& $fail "표식 블록 안이 'Match User $u' + 'PasswordAuthentication no' 가 아님") }
    # 블록 뒤는 다음 Match 줄(다른 전용 계정의 표식 블록·고객 블록)까지만 본다. 새 Match 줄은 앞 Match 블록을 닫으므로 그 뒤 줄은
    # 그 Match 블록 안에 들어가 우리 블록에 섞이지 않고, 같은 키워드는 처음 얻은 값을 쓰므로 뒤 블록이 우리 'no' 를 덮지도 못한다.
    $after = @($lines | Select-Object -Skip ($e + 1) | Where-Object { & $isSetting $_ })
    $stray = 0
    foreach ($l in $after) { if ((($l.Trim() -split '[\s=]+', 2)[0]) -ieq 'match') { break }; $stray++ }
    if ($stray -gt 0) { return (& $fail "표식 블록 뒤에 설정 줄 $($stray)개 (그 줄이 우리 Match 블록 안으로 들어감 - 블록 뒤에는 Match 줄로 시작하는 블록만 와야 함)") }
    $inMatch = $false; $applies = $false; $matchLine = ''
    for ($i = 0; $i -lt $b; $i++) {
        if (-not (& $isSetting $lines[$i])) { continue }
        $t = $lines[$i].Trim()
        $kw = ($t -split '[\s=]+', 2)[0].ToLowerInvariant()
        $rest = if ($t -match '^\S+?(?:\s*=\s*|\s+)(.*)$') { $Matches[1].Trim() } else { '' }
        if ($kw -eq 'include') { return (& $fail "앞쪽에 Include 줄이 있어 정적으로 확인할 수 없음 ($($i + 1)행)") }
        if ($kw -eq 'match') { $inMatch = $true; $matchLine = $t; $applies = Test-SshdMatchMayApply $rest $u $Groups; continue }
        if ($kw -eq 'passwordauthentication' -and $inMatch -and $applies -and ($rest -split '\s+')[0] -ine 'no') {
            return (& $fail "앞선 '$matchLine' 블록($($i + 1)행)의 PasswordAuthentication $rest 이 이 계정에 먼저 적용될 수 있음")
        }
    }
    [pscustomobject]@{ Ok = $true; Reason = '' }
}
