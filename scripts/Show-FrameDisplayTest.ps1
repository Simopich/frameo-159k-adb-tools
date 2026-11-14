$ErrorActionPreference = 'Stop'
$state = Join-Path (Split-Path $PSScriptRoot -Parent) 'work/wireless-display/virtual-display'
Add-Type -Path (Join-Path $PSScriptRoot 'FrameDisplayNative.cs')
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::PerMonitorV2) | Out-Null
$saved = Get-Content -LiteralPath (Join-Path $state 'display.json') -Raw | ConvertFrom-Json
$display = [FrameDisplayNative]::Virtual($saved.Name)
if (-not $display.Active -or $display.Primary -or $display.MonitorId -ne $saved.MonitorId) { throw 'Dedicated virtual monitor is not available.' }
$form = [Windows.Forms.Form]::new()
$form.Text = 'Frameo Extended Display Test'
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.Bounds = [Drawing.Rectangle]::new($display.X,$display.Y,1920,1080)
$form.BackColor = [Drawing.Color]::FromArgb(12,32,72)
$form.ShowInTaskbar = $false
$label = [Windows.Forms.Label]::new()
$label.Dock = 'Fill'
$label.TextAlign = 'MiddleCenter'
$label.ForeColor = [Drawing.Color]::White
$label.Font = [Drawing.Font]::new('Segoe UI',40)
$form.Controls.Add($label)
$timer = [Windows.Forms.Timer]::new()
$timer.Interval = 1000
$timer.Add_Tick({$label.Text = "FRAMEO EXTENDED DISPLAY`n`nIndependent Windows workspace`n1920 x 1080 | 60 Hz`n`n$([DateTime]::Now.ToString('HH:mm:ss'))`n`nMove a window here from your PC.`nAlt+F4 closes this test."})
$timer.Start()
$form.Add_Shown({ $form.Bounds | Select-Object X,Y,Width,Height | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $state 'test-window-bounds.json') })
$PID | Set-Content -LiteralPath (Join-Path $state 'test-window.pid')
[Windows.Forms.Application]::Run($form)
$timer.Dispose()
$form.Dispose()
