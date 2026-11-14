# Wireless PC display on the Frameo 159K

## Installed and verified on November 14, 2026

The frame runs **AVNC 3.3.1**, an open-source native Android VNC receiver (`com.gaurav.avnc`, GPL-3.0-or-later). Its minimum Android version is 5.0/API 21; this frame runs Android 8.1/API 27. The official APK supports the frame's ARM architectures. The saved connection is named **PC Wireless Display** and is view-only.

The PC runs **TightVNC 2.8.90 GPL**, extracted locally and launched in application mode. It is not registered as a Windows service or automatic startup task. **TightVNC 4 is closed source** and was deliberately not selected. No display driver, firewall exception, Android boot setting, HOME default or Frameo package was changed.

End-to-end verification succeeded: a frame screenshot showed the current Windows desktop, and Windows reported established TCP connections from the frame to the companion on port 5909. The private screenshot remains under ignored `work/wireless-display/`; do not publish it because it contains desktop content. This verifies mirroring, not measured latency or frame rate.

## Start and stop on this PC

Run in PowerShell 7 from this repository:

```powershell
./scripts/Start-WirelessDisplay.ps1
./scripts/Start-WirelessDisplay.ps1 -Stop
```

The existing private `work/wireless-display/connection.json` supplies this PC's ADB path and the current LAN addresses. Start launches the PC companion, opens AVNC, and updates the saved profile without creating duplicates. Stop closes only this extracted companion. AVNC remains installed. The script must be run again after Windows restarts or the companion exits; there is no automatic startup. With the companion already running, open AVNC on the frame and select **PC Wireless Display** without using ADB again.

If DHCP changes either address, update the private connection file or override the values:

```powershell
./scripts/Start-WirelessDisplay.ps1 -Target FRAME_IP:5555 -HostAddress PC_IP -Adb 'C:/path/to/adb.exe'
```

Both devices must be on the same trusted LAN. The script restricts TightVNC's IPv4 access list to the frame's current IP and localhost, denies other IPv4 addresses, disables file transfer and remote input, and enables VNC authentication. It shares the PC's primary monitor. The tested IPv4 listener is on `0.0.0.0:5909`; it is **not** a loopback-only listener. No firewall was disabled or rule added. If another PC's firewall blocks it, allow only this executable, TCP port 5909, the private network profile and the frame's source IP; do not expose the port to the Internet.

Classic TightVNC 2 traffic is **not encrypted**. Its eight-character VNC password is generated locally, saved with Windows DPAPI in ignored `password.xml`, and stored by TightVNC using its legacy reversible registry format. AVNC also saves the connection password in its private app data. These are not equivalent to end-to-end encrypted credentials. Use only the trusted LAN; use an SSH/TLS-capable server for untrusted networks. Credentials are never printed by the launcher or committed. VNC credentials in ActivityManager intents can remain visible to privileged local inspection.

## Reproducing the installation

1. Download [AVNC's official v3.3.1 APK](https://github.com/gujjwal00/avnc/releases/tag/v3.3.1). Its SHA256 must equal `61cb507e9f334f0276eacc8e9574bae6934d18e59c96b49f900a1183637d8f88`. Install it with authenticated ADB.
2. Download the **2.8.90 GPL 64-bit MSI** from the [official TightVNC download page](https://www.tightvnc.com/download.php). On this PC its Authenticode signature was valid and identified GlavSoft. Retain the license alongside the extracted executables. Do not substitute version 4.
3. Perform an administrative extraction, not a service installation:

```powershell
$package = (Resolve-Path './work/wireless-display/tightvnc-2.8.90-gpl-setup-64bit.msi').Path
$destination = Join-Path (Resolve-Path './work/wireless-display').Path 'tightvnc-portable'
Start-Process msiexec.exe -WindowStyle Hidden -Wait -ArgumentList '/a', ('"'+$package+'"'), '/qn', ('TARGETDIR="'+$destination+'"')
```

4. Create ignored `work/wireless-display/connection.json` with string properties `Target` (`FRAME_IP:5555`), `HostAddress` (`PC_IP`) and `Adb` (the executable's absolute path), or pass those parameters explicitly. Run the launcher. A pre-existing, unrelated TightVNC user configuration or process causes a refusal so it is not overwritten.

The launcher owns only its marked `HKCU:\Software\TightVNC\Server` configuration, the ignored local companion files and the AVNC connection profile. To remove the setup, stop it, uninstall AVNC, delete its ignored local files after preserving anything needed, and remove that registry key only after verifying `FrameoManaged=1` and confirming no other TightVNC configuration has replaced it. No system service or display driver needs removal.

## Mirroring versus an extended desktop

AVNC and TightVNC share an existing Windows monitor. They do **not** create an additional Windows display. For a genuinely independent extended desktop, Windows must first have another physical or virtual display. Sharing that display then becomes possible, for example with TightVNC's `-sharedisplay` option. No virtual display driver was installed or tested in this task.

The frame has about 1 GB RAM and an older Rockchip chipset. VNC is suitable for reference windows and relatively static information; it should not be assumed suitable for gaming or smooth high-frame-rate video. A 16:9 frame can letterbox a differently shaped PC monitor. No audio transport was configured or verified.

[Deskreen CE](https://github.com/pavlobu/deskreen) is also open source (AGPL-3.0) and streams via WebRTC to a browser, but requires a capable browser on the frame and also does not create an extra Windows display by itself. AVNC was selected for its native Android client, API 21 compatibility, small download and independent browser operation. Weylus also uses a browser and provides its strongest integration on Linux. The Android 8.1 firmware rejected Wi-Fi `adb reverse` with `more than one device/emulator` despite a single connected device, so the verified final setup uses direct LAN VNC.

Sources: [AVNC source and features](https://github.com/gujjwal00/avnc), [AVNC Android compatibility on F-Droid](https://f-droid.org/en/packages/com.gaurav.avnc/), [TightVNC licensing](https://www.tightvnc.com/licensing.php), [TightVNC server command-line reference](https://www.tightvnc.com/doc/win/TightVNC_2.7_for_Windows_Server_Command-Line_Options.pdf). Registry access-list and password handling were checked against the official TightVNC 2.8.90 GPL source archive linked from its download page.
