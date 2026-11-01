[CmdletBinding()]
param(
    [string] $BuildTools = './work/android-tools/build-tools_r36_windows/android-16',
    [string] $AndroidJar = './work/android-tools/platform-27_r03/android-8.1.0/android.jar',
    [string] $Java = 'java.exe',
    [ValidateSet('Probe', 'Adb')] [string] $Mode = 'Probe',
    [string] $AdbPublicKey,
    [ValidateRange(80322, 2100000000)] [int] $VersionCode = 80322,
    [string] $Output = './outputs/frameo-159k-sd-probe'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repo
$utf8 = [System.Text.UTF8Encoding]::new($false)
$normalizedPublicKey = $null
if ($Mode -eq 'Adb') {
    if (-not $AdbPublicKey) { throw 'Adb mode requires -AdbPublicKey pointing to adbkey.pub.' }
    $keyPath = (Resolve-Path -LiteralPath $AdbPublicKey).Path
    if ([System.IO.Path]::GetFileName($keyPath) -eq 'adbkey') { throw 'Pass the public .pub key, never the private adbkey.' }
    $keyText = [System.IO.File]::ReadAllText($keyPath)
    $keyLines = @($keyText -split '\r?\n' | Where-Object { $_.Trim() })
    if ($keyLines.Count -ne 1 -or $keyText.Contains('PRIVATE')) { throw 'Invalid public key file.' }
    $blob = ($keyLines[0].Trim() -split '\s+')[0]
    $bytes = [Convert]::FromBase64String($blob)
    if ($bytes.Length -ne 524 -or [BitConverter]::ToUInt32($bytes, 0) -ne 64 -or $blob.Length -ne 700) {
        throw 'Expected an Android ADB RSA2048 public key.'
    }
    $normalizedPublicKey = "$blob frameo-local-pc`n"
}

function Write-Utf8Lf([string] $Path, [string] $Text) {
    [System.IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"), $utf8)
}

function Invoke-Native([string] $Executable, [string[]] $Arguments) {
    $lines = & $Executable @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Native command failed ($LASTEXITCODE): $Executable`n$($lines -join "`n")"
    }
    return ($lines -join "`n")
}

$tools = (Resolve-Path -LiteralPath $BuildTools).Path
$platform = (Resolve-Path -LiteralPath $AndroidJar).Path
$javaPath = (Get-Command $Java -ErrorAction Stop).Source
$keytool = Join-Path (Split-Path -Parent $javaPath) 'keytool.exe'
$aapt = Join-Path $tools 'aapt2.exe'
$zipalign = Join-Path $tools 'zipalign.exe'
$signer = Join-Path $tools 'lib/apksigner.jar'
foreach ($required in @($keytool, $aapt, $zipalign, $signer)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required tool missing: $required" }
}

$out = [System.IO.Path]::GetFullPath($Output, $repo)
$outputsRoot = [System.IO.Path]::GetFullPath((Join-Path $repo 'outputs')) + [System.IO.Path]::DirectorySeparatorChar
if (-not $out.StartsWith($outputsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output must be a child directory of this repository outputs directory.'
}
$archivePath = $out + '.zip'
if ((Test-Path -LiteralPath $out) -or (Test-Path -LiteralPath $archivePath)) {
    throw 'Output already exists. Select a new output path to preserve previous results.'
}
$scratch = Join-Path $repo ('work/sd-probe-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="net.frameo.frame" android:versionCode="$VersionCode" android:versionName="local-diagnostic-$VersionCode">
    <uses-sdk android:minSdkVersion="23" android:targetSdkVersion="27" />
    <application android:label="Local SD diagnostic" android:hasCode="false" android:allowBackup="false" />
</manifest>
"@
$manifestPath = Join-Path $scratch 'AndroidManifest.xml'
Write-Utf8Lf $manifestPath $manifest
$unsigned = Join-Path $scratch 'unsigned.apk'
$aligned = Join-Path $scratch 'aligned.apk'
$signed = Join-Path $scratch 'signed.apk'
$keystore = Join-Path $scratch 'diagnostic-signing.p12'

$null = Invoke-Native $aapt @('link', '-o', $unsigned, '--manifest', $manifestPath, '-I', $platform)
$null = Invoke-Native $zipalign @('-f', '4', $unsigned, $aligned)
$null = Invoke-Native $keytool @('-genkeypair', '-noprompt', '-keystore', $keystore,
    '-storetype', 'PKCS12', '-storepass', 'local-diagnostic-only', '-alias', 'probe',
    '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Local Frameo SD diagnostic')
$null = Invoke-Native $javaPath @('-jar', $signer, 'sign', '--ks', $keystore,
    '--ks-key-alias', 'probe', '--ks-pass', 'pass:local-diagnostic-only',
    '--v1-signing-enabled', 'true', '--v2-signing-enabled', 'true',
    '--v4-signing-enabled', 'false', '--out', $signed, $aligned)
$signature = Invoke-Native $javaPath @('-jar', $signer, 'verify', '--verbose', '--min-sdk-version', '23', $signed)
$badging = Invoke-Native $aapt @('dump', 'badging', $signed)
if ($badging -notmatch "name='net\.frameo\.frame' versionCode='$VersionCode'") { throw 'APK identity verification failed.' }
if ($badging -notmatch "sdkVersion:'23'") { throw 'APK minimum API verification failed.' }
if ($signature -notmatch 'Verified using v1 scheme \(JAR signing\): true') { throw 'APK v1 signature verification failed.' }

$apk = [System.IO.Compression.ZipFile]::OpenRead($signed)
try {
    if (@($apk.Entries | Where-Object { $_.FullName -match '(^|/)classes\d*\.dex$' }).Count -ne 0) {
        throw 'Diagnostic APK must contain no executable DEX.'
    }
} finally { $apk.Dispose() }

$card = Join-Path $out 'sd'
$utilities = Join-Path $card 'Frameo_utilities'
New-Item -ItemType Directory -Path $utilities -Force | Out-Null
$payloadName = 'x'';sh${IFS}$(find${IFS}${ANDROID_DATA%data}storage${IFS}-maxdepth${IFS}2${IFS}-name${IFS}p_frameo_jb);#.apk'
Copy-Item -LiteralPath $signed -Destination (Join-Path $utilities $payloadName)
Write-Utf8Lf (Join-Path $utilities 'frameo_utilities.config') "auto_run=action_update_version`n"
$deviceScript = if ($Mode -eq 'Adb') { 'sd-enable-adb.sh' } else { 'sd-probe.sh' }
$probe = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot $deviceScript))
Write-Utf8Lf (Join-Path $card 'p_frameo_jb') $probe
if ($Mode -eq 'Adb') {
    $adbState = Join-Path $card 'frameo-159k-adb'
    New-Item -ItemType Directory -Path $adbState | Out-Null
    Write-Utf8Lf (Join-Path $adbState 'adbkey.pub') $normalizedPublicKey
}
$instructions = @'
FRAMEO 159K DIAGNOSTIC TEST - device compatibility not yet verified

Copy these files directly to the microSD root, preserving every filename exactly.
Never paste the APK filename into a terminal: it contains shell syntax.
Open Settings on the frame and insert the card. Wait 20-30 seconds.
Inspect the script log regardless of the update task's success or error message.
Read the card on the PC and find frameo-159k-probe.txt at the card root.
The test reads Android information and writes only its log and marker to the card.
It does not invoke su, enable ADB, change settings, or write firmware.
Remove the package files from the card after the test.
'@
Write-Utf8Lf (Join-Path $card 'README.txt') ($instructions + "`n")
if ($Mode -eq 'Adb') {
    $adbInstructions = @'
AUTHENTICATED WI-FI ADB - FIRST, TEMPORARY CONNECTION

Only for the exact 159K firmware verified by the diagnostic log.
The code checks model, platform, API, build and fingerprint before changing settings.
It adds only the PC public key, preserves previous keys, and enables TCP 5555.
It retains ro.adb.secure=1; reboot persistence is a separate step.
It saves the baseline and result in frameo-159k-adb on the card.
On failure it attempts rollback and records whether rollback was verified.

Open Settings on the frame, insert the card, and wait 30 seconds.
Close the task with Complete task. Leave the frame powered on and on the same LAN.
The PC must still verify adb connect and an authenticated shell.
APK successfully installed alone does not prove that ADB works.
The unusual APK filename contains shell syntax: never paste it into a terminal.
Private key files are not included in this package.
'@
    Write-Utf8Lf (Join-Path $card 'README.txt') ($adbInstructions + "`n")
}

$inventory = @()
$zip = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in (Get-ChildItem -LiteralPath $card -Recurse -File | Sort-Object FullName)) {
        $relative = [System.IO.Path]::GetRelativePath($card, $file.FullName).Replace('\', '/')
        $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relative)
        $inventory += [ordered]@{ path = $relative; bytes = $file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
} finally { $zip.Dispose() }

$verificationDir = Join-Path $scratch 'archive-readback'
[System.IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $verificationDir)
foreach ($entry in $inventory) {
    $extracted = Join-Path $verificationDir $entry.path
    if ((Get-FileHash -LiteralPath $extracted -Algorithm SHA256).Hash -ne $entry.sha256) {
        throw "Archive readback verification failed: $($entry.path)"
    }
}
$metadata = [ordered]@{
    schema = 'frameo-sd-package/v1'
    mode = $Mode
    tested_on_device = $false
    intended_frameo_version_code = 80321
    apk_version_code = $VersionCode
    apk_contains_dex = $false
    apk_v1_signature_verified = $true
    archive_readback_verified = $true
    archive_sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    files = $inventory
}
Write-Utf8Lf (Join-Path $out 'manifest.json') (($metadata | ConvertTo-Json -Depth 6) + "`n")
Write-Utf8Lf (Join-Path $out 'apk-verification.txt') ($signature + "`n" + $badging + "`n")
Write-Output "Verified package: $archivePath"
Write-Output "SD card files: $card"
Write-Output 'Device verification is still required.'
