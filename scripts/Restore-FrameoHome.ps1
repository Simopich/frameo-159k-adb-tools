[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Adb,
    [Parameter(Mandatory = $true)][string]$Target,
    [ValidateSet('Stock', 'Nova')][string]$Launcher = 'Stock'
)
$ErrorActionPreference = 'Stop'
function Invoke-Adb([string[]]$Arguments) {
    $result = & $Adb -s $Target @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -or ($result -join "`n") -match '(?m)^Error:|Exception') {
        throw ($result -join [Environment]::NewLine)
    }
    $result
}
Invoke-Adb @('get-state')
$component = if ($Launcher -eq 'Stock') {
    'net.frameo.frame/.ui.activities.AWaitForDeferredInitCompleted'
} else {
    'com.teslacoilsw.launcher/.NovaLauncher'
}
Invoke-Adb @('shell', 'cmd', 'package', 'set-home-activity', '--user', '0', $component)
if ($Launcher -eq 'Stock') {
    Invoke-Adb @('shell', "su -c 'pm default-state --user 0 net.frameo.frame/.core.BootCompleteReceiver'")
    Invoke-Adb @('shell', "su -c 'pm default-state --user 0 net.frameo.frame/com.instacart.library.truetime.BootCompletedBroadcastReceiver'")
}
$resolved = Invoke-Adb @('shell', 'cmd', 'package', 'resolve-activity', '--brief', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME')
if (($resolved -join "`n") -notlike "*$component*") { throw 'The requested HOME did not become the default.' }
$resolved
# Persist the choice before launching stock, which can perform its own updates.
$parts = $component.Split('/')
$fullComponent = $parts[0] + '/' + $(if ($parts[1].StartsWith('.')) { $parts[0] + $parts[1] } else { $parts[1] })
$persisted = $false
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    $restrictions = Invoke-Adb @('shell', "su -c 'cat /data/system/users/0/package-restrictions.xml'")
    $settings = [xml]($restrictions -join "`n")
    if ($settings.SelectSingleNode("package-restrictions/preferred-activities/item[@name='$component' or @name='$fullComponent']")) {
        $persisted = $true
        break
    }
    Start-Sleep -Seconds 1
}
if (-not $persisted) { throw 'HOME did not reach persistent package restrictions; recovery activity was not launched.' }
Invoke-Adb @('shell', 'am', 'start', '-W', '-n', $component)
Write-Output "$Launcher HOME selected. No app data, firmware, or ADB settings were changed."
