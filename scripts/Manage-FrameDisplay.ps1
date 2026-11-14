param([ValidateSet('Start','Stop','Remove','Status','Watch')][string]$Action = 'Status', [int]$OwnerProcessId)
$ErrorActionPreference = 'Stop'
$state = Join-Path (Split-Path $PSScriptRoot -Parent) 'work/wireless-display/virtual-display'
$tool = Join-Path $state 'vdisplay/vdisplay.exe'
$toolState = Join-Path $state 'vdisplay/vdisplay.state'
$displayPath = Join-Path $state 'display.json'
$expectedId = '252b4321b1718db1bc4311f570fd9be2'
$server = Join-Path (Split-Path $state -Parent) 'tightvnc-portable/PFiles/TightVNC/tvnserver.exe'
$watchPath = Join-Path $state 'capture-watch.pid'
if (@(Get-Process vdisplay -ErrorAction SilentlyContinue | Where-Object { $_.Path -ne $tool }).Count) { throw 'Another vdisplay controller is running. Refusing to change its monitor.' }
if (-not ('FrameDisplayNative' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'FrameDisplayNative.cs') }
function Invoke-DisplayTool([string[]]$Arguments) {
    if (-not (Test-Path -LiteralPath $tool)) { throw 'Download the verified vdisplay 0.1.0 release as documented in wireless-display.md.' }
    if ((Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash -ne '07AA347F5803F2DE3821364BA30FAF5B6A530F416FAEA767A5B54CB39A46D170') { throw 'Unexpected vdisplay executable hash.' }
    $log = Join-Path $state ('command-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $process = Start-Process -FilePath $tool -ArgumentList $Arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $log
    if (-not $process.WaitForExit(35000)) { throw 'Timed out waiting for the virtual display controller.' }
    $output = Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
    if ($process.ExitCode -ne 0) { throw "Virtual display controller failed. See $log and vdisplay/vdisplay.log." }
    return $output
}
function Assert-OwnedState {
    if ((Test-Path -LiteralPath $toolState) -and (Get-Content -LiteralPath $toolState -Raw).Trim() -ne $expectedId) {
        throw 'Another vdisplay monitor owns this controller. Refusing to change or remove it.'
    }
}
function Stop-Companion {
    Get-Process tvnserver -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $server } | Stop-Process
}
if ($Action -in @('Stop','Remove')) {
    Assert-OwnedState
    if ($Action -eq 'Stop') { Stop-Companion }
    if (Test-Path -LiteralPath $watchPath) { Remove-Item -LiteralPath $watchPath }
    Invoke-DisplayTool @('stop') | Out-Null
    if (Test-Path -LiteralPath $displayPath) { Remove-Item -LiteralPath $displayPath }
    Write-Output 'Dedicated virtual monitor removed. Existing Apollo driver and physical displays remain.'
    return
}
if ($Action -eq 'Start') {
    Assert-OwnedState
    $before = @([FrameDisplayNative]::List() | Where-Object Active)
    $controllerStatus = Invoke-DisplayTool @('status')
    $display = $null
    if ($controllerStatus -match '(?m)^active\s*$' -and (Test-Path -LiteralPath $displayPath)) {
        $saved = Get-Content -LiteralPath $displayPath -Raw | ConvertFrom-Json
        $display = [FrameDisplayNative]::List() | Where-Object { $_.Name -eq $saved.Name -and $_.MonitorId -eq $saved.MonitorId -and $_.Active }
    }
    if (-not $display) {
        # A dedicated, stable identity lets Windows remember this monitor's layout.
        # Never use --primary, --exclusive, install-driver or uninstall-driver here.
        $arguments = @('start','--width','1920','--height','1080','--fps','60','--no-hdr','--name','"Frameo Extended Display"','--id','frameo-159k-dedicated-display','--no-watch')
        if ($OwnerProcessId) { $arguments += @('--watch-pid',[string]$OwnerProcessId) }
        $output = Invoke-DisplayTool $arguments
        $names = @($output -split '\r?\n' | Where-Object { $_ -match '^\\\\\.\\DISPLAY\d+$' })
        if ($names.Count -ne 1) { throw 'Controller returned an unexpected display name.' }
        $name = $names[0]
        $display = [FrameDisplayNative]::Virtual($name)
    }
    $display = [FrameDisplayNative]::Extend($display.Name, 1920, 1080, 60)
    $after = [FrameDisplayNative]::List()
    foreach ($old in $before | Where-Object { $_.Name -ne $display.Name }) {
        $current = $after | Where-Object Name -eq $old.Name
        foreach ($property in @('Active','Primary','X','Y','Width','Height','RefreshRate','Orientation')) {
            if ($current.$property -ne $old.$property) { throw "Existing display changed unexpectedly: $($old.Name), $property." }
        }
    }
    $display | ConvertTo-Json | Set-Content -LiteralPath $displayPath
    return $display
}
if ($Action -eq 'Status') {
    Invoke-DisplayTool @('status')
    [FrameDisplayNative]::List() | Where-Object Active
    return
}
# Fail closed if the dedicated display disappears or its geometry changes.
if (-not (Test-Path -LiteralPath $displayPath)) { return }
$expected = Get-Content -LiteralPath $displayPath -Raw | ConvertFrom-Json
$PID | Set-Content -LiteralPath $watchPath
while (Get-Process tvnserver -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $server }) {
    if (-not (Test-Path -LiteralPath $watchPath) -or [int](Get-Content -LiteralPath $watchPath) -ne $PID) { break }
    $displays = [FrameDisplayNative]::List()
    $current = $displays | Where-Object { $_.Name -eq $expected.Name -and $_.MonitorId -eq $expected.MonitorId -and $_.Active }
    $overlap = @($displays | Where-Object { $_.Active -and $_.Name -ne $expected.Name -and $_.X -lt ($expected.X+1920) -and ($_.X+$_.Width) -gt $expected.X -and $_.Y -lt ($expected.Y+1080) -and ($_.Y+$_.Height) -gt $expected.Y }).Count
    if (-not $current -or $overlap -or $current.Primary -or $current.X -ne $expected.X -or $current.Y -ne $expected.Y -or $current.Width -ne 1920 -or $current.Height -ne 1080) {
        Stop-Companion
        'Capture stopped because the dedicated virtual display changed.' | Set-Content -LiteralPath (Join-Path $state 'capture-guard.txt')
        break
    }
    Start-Sleep -Seconds 1
}
