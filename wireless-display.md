# Independent extended PC display on the Frameo 159K

The frame is a separate Windows desktop display, **1920×1080 at a configured 60 Hz**. AVNC receives only this virtual display through TightVNC. The physical PC monitor remains primary. Move a window beyond the PC monitor's right edge to put it on the frame.

## Use and rollback

Run PowerShell 7 from this repository:

```powershell
./scripts/Start-WirelessDisplay.ps1
./scripts/Start-WirelessDisplay.ps1 -Stop
```

Start opens a black idle VNC listener and AVNC's saved **PC Wireless Display** profile. Only a real authenticated frame session creates the dedicated monitor and switches capture to its rectangle. AVNC is view-only: use the PC's mouse and keyboard to work on this desktop. The launcher restarts AVNC to clear stale connection dialogs.

The lifetime follows the VNC session, not the foreground Android app. Returning to the dashboard can leave AVNC connected in the background. To remove the monitor, explicitly disconnect the session in AVNC, or run Stop on the PC.

Stop closes this TightVNC companion and removes only this dedicated monitor. It leaves Apollo, SudoVDA, other monitors and the physical display intact. No reboot or driver removal is required. After Windows restarts, run Start again; no automatic logon task was added. A detached session supervisor keeps working after PowerShell closes. The virtual monitor disappears automatically about 3 seconds after VNC disconnects. The black listener stays available: opening the saved AVNC profile again recreates the monitor without rerunning Start. The `vdisplay` keeper also watches the supervisor process, removing its monitor if the supervisor dies.

Do not change the dedicated monitor to duplicate mode or make it primary. The launcher requires an independent, non-primary 1920×1080 desktop and recalculates its rectangle on each run. The supervisor stops capture if its monitor disappears unexpectedly, moves, changes resolution, becomes primary or overlaps another active display. It polls every 500 ms, so it is a recovery safeguard rather than an atomic security boundary. Run Start again after changing display layout.

## Verified result: November 14, 2026

This PC runs Windows 11 Pro build 26200 with an AMD Radeon RX 7700 XT and AMD integrated graphics. Apollo and **SudoMaker Virtual Display Adapter 1.10.9.289** were already installed. This integration reused the existing driver. It did not install a second driver, certificate, service or firewall rule; change boot security; restart Windows; or change Apollo settings.

| Display | Position | Resolution | Refresh rate | Primary |
| --- | --- | --- | --- | --- |
| Existing physical monitor | 0, 0 | 3440×1440 | 180 Hz | Yes |
| Dedicated Frameo desktop | 3440, 0 | 1920×1080 | 60 Hz | No |

The disjoint desktop geometry was enumerated through Win32. The physical monitor's position, resolution, orientation, primary status and refresh rate matched the baseline after creation, repeated launcher invocation, removal and recreation of the virtual monitor.

A full-screen test window occupied only `3440,0,1920,1080`, outside the physical monitor. The frame screenshot showed **FRAMEO EXTENDED DISPLAY**, **Independent Windows workspace** and a live clock. TightVNC shared only `1920x1080+3440+0`. The test window was closed after verification. A real AVNC force-stop then removed the virtual monitor while the physical monitor remained unchanged and the VNC listener stayed open. Reopening only the saved AVNC profile recreated the extended monitor through the same running supervisor. Private screenshots and layout snapshots remain under ignored `work/wireless-display/virtual-display/`.

An optional test window can be opened in another process:

```powershell
pwsh -NoProfile -File ./scripts/Show-FrameDisplayTest.ps1
```

Close it with Alt+F4 on the PC before stopping the display, so Windows does not relocate this test window to the physical screen.

## Components and provenance

- **[AVNC 3.3.1](https://github.com/gujjwal00/avnc/releases/tag/v3.3.1)**, GPL-3.0-or-later, is installed as `com.gaurav.avnc`. Android 5.0/API 21 minimum is compatible with this Android 8.1/API 27 frame. Upstream APK SHA256: `61cb507e9f334f0276eacc8e9574bae6934d18e59c96b49f900a1183637d8f88`.
- **[TightVNC 2.8.90 GPL](https://www.tightvnc.com/download.php)** runs from a local MSI extraction in application mode. The installer had a valid GlavSoft Authenticode signature. Its supported `-sharerect` command isolates the virtual desktop. [TightVNC 4 is closed source](https://www.tightvnc.com/licensing.php) and is not used.
- **[vdisplay 0.1.0](https://github.com/Zayrick/sunshine-vdisplay/releases/tag/v0.1.0)**, GPL-3.0, controls the existing SudoVDA adapter without administrator privileges. Release ZIP SHA256: `638579cecdf4675f5eb956e1ca5962a32eb747181b9303ead5b6041dfb1272e5`. Extracted executable SHA256: `07aa347f5803f2de3821364ba30faf5b6a530f416faea767a5b54cb39a46d170`, checked by the launcher. The new upstream controller is version 0.1.0; this integration was tested on this PC. It is not represented as an Authenticode-signed application.
- **[SudoVDA](https://github.com/SudoMaker/SudoVDA)** publishes source under MIT/CC0/public-domain terms stated in its README. The driver was already installed with Apollo; its existing signing and trust state were not changed. This launcher never invokes `install-driver`, `uninstall-driver`, `--primary` or `--exclusive`, imports certificates, or changes Secure Boot or signature enforcement.

The dedicated controller identity is `frameo-159k-dedicated-display`, separate from Apollo client identities. Do not uninstall the shared SudoVDA driver as rollback: that would disrupt the existing Apollo installation.

## Local configuration and reproduction

Downloads, credentials, LAN settings and logs stay in ignored `work/wireless-display/`. No binaries or real connection credentials are committed. The private `connection.json` contains `Target` (`FRAME_IP:5555`), `HostAddress` (`PC_IP`) and `Adb` (absolute executable path). If DHCP changes an address, update it or override:

```powershell
./scripts/Start-WirelessDisplay.ps1 -Target FRAME_IP:5555 -HostAddress PC_IP -Adb 'C:/path/to/adb.exe'
```

For another checkout on this PC, download the official `vdisplay-v0.1.0-windows-x64.zip`, verify the hashes above, and extract it into `work/wireless-display/virtual-display/vdisplay/`, retaining its license. The expected program path is `vdisplay/vdisplay.exe`. The existing SudoVDA driver is required; the launcher does not install drivers automatically.

Download the official **TightVNC 2.8.90 GPL 64-bit MSI**, retain its license, and extract it without installing a service:

```powershell
$package = (Resolve-Path './work/wireless-display/tightvnc-2.8.90-gpl-setup-64bit.msi').Path
$destination = Join-Path (Resolve-Path './work/wireless-display').Path 'tightvnc-portable'
Start-Process msiexec.exe -WindowStyle Hidden -Wait -ArgumentList '/a', ('"'+$package+'"'), '/qn', ('TARGETDIR="'+$destination+'"')
```

The expected program path is `tightvnc-portable/PFiles/TightVNC/tvnserver.exe`. Install the verified AVNC APK using authenticated ADB, create the private connection file, and run Start. Existing unrelated TightVNC configuration or another `vdisplay` executable causes a refusal rather than being overwritten or stopped.

## Network and limits

Both devices must be on the same trusted LAN. TightVNC's IPv4 ACL allows only the frame's current IP, denies loopback and other IPv4 addresses, disables file transfer and remote input, and requires VNC authentication. It listens on IPv4 port 5909. No firewall was disabled or rule added. Do not expose this port to the Internet. Any firewall exception needed on another PC should be limited to this executable, TCP 5909, the private profile and the frame's source IP.

Classic TightVNC 2 traffic is **not encrypted**. Its eight-character password is generated locally, protected with Windows DPAPI in ignored `password.xml`, stored by TightVNC in its legacy reversible registry format, and saved by AVNC in private app data. Credentials are not printed or committed; privileged local inspection can still see ActivityManager intents. Use an SSH/TLS-capable server for untrusted networks.

The virtual monitor's configured 60 Hz does not imply 60 fps delivery. VNC on this older Rockchip frame with approximately 1 GB RAM suits reference windows and relatively static information. Latency, sustained frame rate and audio were not measured or configured. The Android global dashboard gesture, Dev HOME and accessibility service remain unchanged.

Deskreen CE and Weylus use a browser and do not create an extended Windows monitor by themselves. The earlier AVNC setup mirrored the physical display; this configuration replaces it with a session-bound independent desktop. Android 8.1 rejected Wi-Fi `adb reverse`, so final transport is direct LAN VNC.

For full feature removal, stop first, uninstall AVNC, and remove the ignored feature files after preserving anything needed. Its TightVNC registry configuration is marked `FrameoManaged=1` at `HKCU:\Software\TightVNC\Server`; remove that key only after verifying no other configuration has replaced it. Leave the existing Apollo/SudoVDA installation and certificates untouched.

References: [vdisplay lifecycle and commands](https://github.com/Zayrick/sunshine-vdisplay), [TightVNC command-line reference](https://www.tightvnc.com/doc/win/TightVNC_2.7_for_Windows_Server_Command-Line_Options.pdf), [AVNC compatibility](https://f-droid.org/en/packages/com.gaurav.avnc/). TightVNC access-list syntax was checked against the official 2.8.90 GPL source.

## Session detection and failure behavior

The supervisor combines an established socket from the permitted frame IP with TightVNC's official RFB log evidence: `Entering normal phase of the RFB protocol` or normal-phase framebuffer update requests. A ping, open TCP connection or failed authentication alone does not create the display. Info-level logging is enabled only while waiting for authentication; active sessions use level 3 to avoid continuous framebuffer metadata logs. No screen pixels or VNC passwords are logged.

TightVNC's application log is in the current user's `AppData/Roaming/TightVNC/tvnserver.log`. The supervisor reads only this launcher's server PID and starts with a fresh authentication state on every restart. A replaced/truncated log or control failure stops capture and removes the dedicated monitor. An 8 MiB runtime log limit stops the companion rather than allowing unlimited growth; restarting the launcher uses TightVNC's standard five-backup rotation.

Idle capture uses the official `-shareapp` command for the hidden supervisor process, which has no visible windows, producing a black framebuffer. On disconnect it switches back to this black capture before removing the dedicated monitor. During a new handshake the frame may briefly receive this black framebuffer at the physical desktop's dimensions; no physical desktop pixels are intentionally shared. The running session is then resized to the dedicated 1920×1080 rectangle. Physical network loss is detected when Windows/TightVNC reports the session closed, so its transport timeout may precede the 3-second debounce.

The local named-pipe client-list API was investigated but rejects other executables by design. That restriction was respected; the integration uses official CLI commands and supported logs instead. The global dashboard gesture, Dev HOME and accessibility service are not modified.
