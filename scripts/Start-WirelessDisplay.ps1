param(
    [string]$Target,
    [string]$Adb,
    [int]$Port = 5909,
    [string]$HostAddress,
    [switch]$Stop
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$state = Join-Path $root 'work/wireless-display'
$connectionPath = Join-Path $state 'connection.json'
if (Test-Path -LiteralPath $connectionPath) {
    $connection = Get-Content -LiteralPath $connectionPath -Raw | ConvertFrom-Json
    if (-not $Target) { $Target = $connection.Target }
    if (-not $Adb) { $Adb = $connection.Adb }
    if (-not $HostAddress) { $HostAddress = $connection.HostAddress }
}
if (-not $Adb) { $Adb = 'adb.exe' }
if (-not $Target -or (-not $Stop -and -not $HostAddress)) { throw 'Specify -Target FRAME_IP:5555 and -HostAddress PC_IP, or create the private connection.json described in wireless-display.md.' }
if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Port must be between 1024 and 65535.' }
if ($Target -notmatch '^\d{1,3}(\.\d{1,3}){3}:\d+$') { throw 'Target must be an IPv4 ADB endpoint.' }
if (-not $Stop -and $HostAddress -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw 'HostAddress must be an IPv4 address.' }
$server = Join-Path $state 'tightvnc-portable/PFiles/TightVNC/tvnserver.exe'
$key = 'HKCU:\Software\TightVNC\Server'
if (-not (Test-Path -LiteralPath $server)) { throw 'Extract the official TightVNC 2.8.90 GPL MSI as documented in wireless-display.md.' }
$existing = if (Test-Path $key) { Get-ItemProperty $key } else { $null }
if ($existing -and $existing.FrameoManaged -ne 1) { throw 'Existing TightVNC user configuration detected. Preserve it and configure a separate companion manually.' }
if (@(Get-Process tvnserver -ErrorAction SilentlyContinue | Where-Object { $_.Path -ne $server }).Count) { throw 'Another TightVNC server is running. Stop it or configure this companion separately.' }
if ($Stop) {
    $processes = Get-Process tvnserver -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $server }
    $processes | Stop-Process
    Write-Output 'Wireless display stopped. AVNC and the local companion remain installed.'
    return
}
& $Adb connect $Target | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'ADB connection failed.' }
$credentialPath = Join-Path $state 'password.xml'
if (Test-Path -LiteralPath $credentialPath) {
    $credential = Import-Clixml -LiteralPath $credentialPath
} else {
    $bytes = [byte[]]::new(6)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $secure = ConvertTo-SecureString ([Convert]::ToBase64String($bytes)) -AsPlainText -Force
    $credential = [PSCredential]::new('frame-display', $secure)
    $credential | Export-Clixml -LiteralPath $credentialPath
}
$password = $credential.GetNetworkCredential().Password
# TightVNC's legacy password storage uses DES with bit-reversed key bytes.
# Restrict the LAN connection to the frame's IP; classic VNC is not encrypted.
$des = [Security.Cryptography.DES]::Create()
$des.Mode = [Security.Cryptography.CipherMode]::ECB
$des.Padding = [Security.Cryptography.PaddingMode]::None
$des.Key = [byte[]](232,74,214,96,196,114,26,224)
$encrypted = $des.CreateEncryptor().TransformFinalBlock([Text.Encoding]::ASCII.GetBytes($password), 0, 8)
$des.Dispose()
New-Item -Path $key -Force | Out-Null
$settings = @{FrameoManaged=1; RfbPort=$Port; AcceptRfbConnections=1; UseVncAuthentication=1; LoopbackOnly=0; AllowLoopback=1; AcceptHttpConnections=0; EnableFileTransfers=0; BlockRemoteInput=1; RemoveWallpaper=0; RunControlInterface=1}
foreach ($name in $settings.Keys) { New-ItemProperty -Path $key -Name $name -Value $settings[$name] -PropertyType DWord -Force | Out-Null }
New-ItemProperty -Path $key -Name IpAccessControl -Value (($Target.Split(':')[0])+':0,127.0.0.1:0,0.0.0.0-255.255.255.255:1') -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name Password -Value $encrypted -PropertyType Binary -Force | Out-Null
$process = Get-Process tvnserver -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $server }
if (-not $process) { Start-Process -FilePath $server -ArgumentList '-run' -WindowStyle Hidden | Out-Null }
else { & $server -controlapp -reload | Out-Null }
Start-Sleep -Seconds 2
$listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
$serverPids = @(Get-Process tvnserver -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $server } | Select-Object -ExpandProperty Id)
if (-not $listeners -or @($listeners | Where-Object { $_.OwningProcess -notin $serverPids }).Count) {
    Get-Process tvnserver -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $server } | Stop-Process
    throw 'VNC listener was not verified; companion stopped.'
}
& $server -controlapp -shareprimary | Out-Null
$uri = 'vnc://' + $HostAddress + ':' + $Port + '?VncPassword=' + [Uri]::EscapeDataString($password) + '&ConnectionName=PC%20Wireless%20Display&ViewOnly=true&SaveConnection=true'
# Suppress ActivityManager output because it echoes the credential-bearing URI.
& $Adb -s $Target shell am start -a android.intent.action.VIEW -p com.gaurav.avnc -d ('"' + $uri + '"') *> $null
if ($LASTEXITCODE -ne 0) { throw 'Could not open AVNC.' }
Remove-Variable password,uri,encrypted
Write-Output 'Wireless display started: primary PC monitor, view-only VNC, restricted to the frame IP. No service or firewall rule installed.'
