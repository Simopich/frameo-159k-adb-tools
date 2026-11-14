param([Parameter(Mandatory)][string]$FrameAddress, [Parameter(Mandatory)][int]$ServerProcessId, [int]$Port=5909)
$ErrorActionPreference = 'Stop'
$state = Join-Path (Split-Path $PSScriptRoot -Parent) 'work/wireless-display'
$virtual = Join-Path $state 'virtual-display'
$server = Join-Path $state 'tightvnc-portable/PFiles/TightVNC/tvnserver.exe'
$stopFile = Join-Path $virtual 'lifecycle-stop'
$pidFile = Join-Path $virtual 'lifecycle.pid'
$statusFile = Join-Path $virtual 'lifecycle.json'
$readyFile = Join-Path $virtual 'lifecycle-ready'
$logFile = Join-Path $env:APPDATA 'TightVNC/tvnserver.log'
$key = 'HKCU:\Software\TightVNC\Server'
Add-Type -Path (Join-Path $PSScriptRoot 'FrameDisplayNative.cs')
function Control([string[]]$Arguments) {
    $process=Start-Process -FilePath $server -ArgumentList (@('-controlapp')+$Arguments) -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(5000)) { throw 'TightVNC control command timed out.' }
    if ($process.ExitCode -ne 0) { throw 'TightVNC control command failed.' }
}
function State([string]$Phase) {
    @{Phase=$Phase;SupervisorPid=$PID;ChangedAt=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $statusFile
}
function LogLevel([int]$Level) {
    if ($script:lastLevel -ne $Level) {
        New-ItemProperty -Path $key -Name LogLevel -Value $Level -PropertyType DWord -Force | Out-Null
        Control @('-reload')
        $script:lastLevel=$Level
    }
}
$PID | Set-Content -LiteralPath $pidFile
$display=$null; $reader=$null; $stream=$null; $normalSession=$false; $capturing=$false; $missingSince=$null; $lastLevel=4
try {
    # No visible window belongs to this hidden process: application-only capture is black.
    Control @('-shareapp',[string]$PID)
    & (Join-Path $PSScriptRoot 'Manage-FrameDisplay.ps1') -Action Remove | Out-Null
    New-ItemProperty -Path $key -Name AcceptRfbConnections -Value 1 -PropertyType DWord -Force | Out-Null
    Control @('-reload')
    $stream=[IO.FileStream]::new($logFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::Unicode,$true,4096,$true)
    State 'waiting-for-authenticated-vnc'
    $PID | Set-Content -LiteralPath $readyFile
    $pending=''
    while (-not (Test-Path -LiteralPath $stopFile) -and (Get-Process -Id $ServerProcessId -ErrorAction SilentlyContinue)) {
        $logLength=(Get-Item -LiteralPath $logFile).Length
        if ($logLength -lt $stream.Position) { throw 'TightVNC log was replaced or truncated; restart the launcher.' }
        if ($logLength -gt 8MB) { throw 'TightVNC log reached the 8 MiB limit; restart the launcher to rotate logs.' }
        $pending += $reader.ReadToEnd()
        $lines=$pending -split "`r`n"
        $pending=$lines[-1]
        for($index=0;$index -lt $lines.Count-1;$index++) {
            $line=$lines[$index]
            if ($line -notmatch ('^\[\s*'+$ServerProcessId+'/')) { continue }
            if ($line -match 'Entering normal phase of the RFB protocol|update requested .*by client') { $normalSession=$true }
            if ($line -match ('Connection from '+[regex]::Escape($FrameAddress)+'.*has been closed')) { $normalSession=$false }
        }
        # Normal-phase evidence is required in addition to an actual frame socket.
        $sockets=@(Get-NetTCPConnection -LocalPort $Port -State Established -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -eq $ServerProcessId -and $_.RemoteAddress -eq $FrameAddress })
        if (-not $sockets.Count) { $normalSession=$false }
        if ($normalSession -and $sockets.Count) {
            $missingSince=$null
            if (-not $display) {
                $display=& (Join-Path $PSScriptRoot 'Manage-FrameDisplay.ps1') -Action Start -OwnerProcessId $PID
            }
            $displays=[FrameDisplayNative]::List()
            $current=$displays | Where-Object { $_.Name -eq $display.Name -and $_.MonitorId -eq $display.MonitorId -and $_.Active }
            $overlap=@($displays | Where-Object { $_.Active -and $_.Name -ne $display.Name -and $_.X -lt ($display.X+1920) -and ($_.X+$_.Width) -gt $display.X -and $_.Y -lt ($display.Y+1080) -and ($_.Y+$_.Height) -gt $display.Y }).Count
            if (-not $current -or $overlap -or $current.Primary -or $current.X -ne $display.X -or $current.Y -ne $display.Y -or $current.Width -ne 1920 -or $current.Height -ne 1080) { throw 'Dedicated display geometry changed; restart the launcher.' }
            if (-not $capturing) {
                $rectangle='{0}x{1}+{2}+{3}' -f 1920,1080,$display.X,$display.Y
                Control @('-sharerect',$rectangle)
                $capturing=$true
                LogLevel 3
                State 'extended-display-active'
            }
        } else {
            LogLevel 4
            if ($capturing) { Control @('-shareapp',[string]$PID); $capturing=$false }
            if (-not $missingSince) { $missingSince=[DateTime]::UtcNow }
            if ($display -and ([DateTime]::UtcNow-$missingSince).TotalSeconds -ge 3) {
                & (Join-Path $PSScriptRoot 'Manage-FrameDisplay.ps1') -Action Remove | Out-Null
                $display=$null
                State 'waiting-for-authenticated-vnc'
            }
        }
        Start-Sleep -Milliseconds 500
    }
} catch {
    $_.Exception.Message | Set-Content -LiteralPath (Join-Path $virtual 'lifecycle-error.txt')
    State 'failed'
} finally {
    try { Control @('-shareapp',[string]$PID) } catch {}
    Get-Process -Id $ServerProcessId -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $server } | Stop-Process
    try { & (Join-Path $PSScriptRoot 'Manage-FrameDisplay.ps1') -Action Remove | Out-Null } catch {}
    if ($reader) { $reader.Dispose() }
    if ($stream) { $stream.Dispose() }
    if (Test-Path -LiteralPath $readyFile) { Remove-Item -LiteralPath $readyFile }
}
