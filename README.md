# Frameo 159K: authenticated, persistent Wi-Fi ADB

Windows PowerShell tools and a report for one owner-controlled Frameo 159K. The SD manufacturer-utility route provided initial root command execution; the firmware's existing network-ADB hook then provided persistence. **Authenticated Wi-Fi ADB was verified after a complete shutdown, a power-adapter change, and a new boot on November 1, 2026.**

ADB was already included in the firmware. This project enables access to it. It does not install a replacement daemon or flash a rooted image.

## Credits and original research

- **[dusty-du/frameo-159k-jailbreak-builder](https://github.com/dusty-du/frameo-159k-jailbreak-builder): the key source for the SD auto-run and APK-filename command-injection mechanism.** Its report covers Frameo 1.30.19 on a 159K. This project adapts the mechanism and checks the unit below; it does not claim discovery of the vulnerability.
- [wesbos/photo-frame-dashboard issue #126](https://github.com/wesbos/photo-frame-dashboard/issues/126): 159K USB/network ADB failures, attempted sideloading and keyboard shortcuts, and discussion of Rockchip's `persist.internet.adb.enable` hook.
- [hbmartin's Dromart MI86 report, PR #262](https://github.com/wesbos/photo-frame-dashboard/pull/262): a reference for the SD diagnostic approach, authenticated access and recovery. It concerns different hardware and Android firmware. Its device-specific ADB enabler was not run on this frame.

The implementation here was prepared with Codex assistance. Device properties, root access and the cold-boot result were checked on the actual frame rather than inferred from other reports.

## Verified device

| Item | Observed value |
| --- | --- |
| Model / device | `159K` / `159K` |
| Firmware-reported brand | `Digital Picture Frame` |
| Firmware-reported manufacturer | `rockchip` (a property value, not an independently identified retail manufacturer) |
| Platform / board / hardware | `rk3326` / `rk30sdk` / `rk30board` |
| ADB product | `rk3326_evb` |
| Primary ABI | `arm64-v8a` |
| ABI list | `arm64-v8a,armeabi-v7a,armeabi` |
| Android | `8.1.0`, API `27` |
| Reported security patch | `2020-11-05` |
| Frameo application | `v1.32.16_-_OTA_test`, versionCode `80321` |
| Factory Frameo APK | `v1.28.14`, versionCode `58400`, `/system/priv-app/newFrameo/newFrameo.apk` |
| Android firmware build | `RK3326_8.1_AY_FRAMEO_202511241509` |
| Build fingerprint | `rockchip/rk3326_evb/rk3326_evb:8.1.0/OC/150829:user/release-keys` |
| Kernel | `4.4.138` |
| Display / density | `1920x1080` / `160 dpi` |
| Reported memory | `MemTotal: 976860 kB` |
| `/data` filesystem size | `58,169,312` 1K blocks; not a measurement of total raw eMMC capacity |
| SELinux | `Permissive` |
| Existing `su` | `/system/xbin/su`; `su -c id` returned UID `0` |
| Normal ADB shell | UID `2000`, context `u:r:shell:s0` |
| ADB authentication | `ro.adb.secure=1`, retained throughout |
| Working SD storage | FAT32 microSD volume of approximately 4 GB |

The Frameo app version and Android firmware build are separate identifiers. Matching `159K` or `80321` alone does not establish compatibility. The retail brand, screen diagonal, raw flash layout and total eMMC capacity have not been independently established here. No serials, MAC addresses, LAN addresses or real host keys are published.

## What did not work

- USB-C to USB-C from the Windows PC did not enumerate an Android/ADB device with Frameo Beta Program and ADB Access enabled. Toggling access did not help. This does not prove the port is physically power-only.
- The frame answered on the LAN, but TCP 5555 initially refused connections. No ADB service was discovered via mDNS.
- Placing the Termux APK at the SD root and inserting the card while Frameo Settings was open did not open an installer.
- Swiping down and Win+N on a keyboard connected to the frame did not expose the notification bar.
- An initial 128 GB card was not recognized; a FAT32 microSD volume of approximately 4 GB worked. The first card's filesystem and the working card's total raw capacity were not measured, so this is not proof of a universal 128 GB limit.

## Scope

Use only on a device you own and on a trusted LAN. The SD mechanism runs commands with the manufacturer's utility privileges. Keep authentication enabled; do not expose TCP 5555 to the Internet. Ordinary TCP ADB should not be treated as encrypted transport.

The successful path used no boot, loader, recovery, system-image or raw-partition writes. Frameo and vendor packages were not disabled or removed. This is a one-unit result, not a universal unlock. Do not bypass firmware checks just because another frame has the same model name.

## 1. Build and run the diagnostic SD package

Requirements: PowerShell 7, JDK 17, official Android SDK build-tools for Windows, a platform `android.jar`, and a microSD card the frame can read. Tested host tooling: platform-tools 37.0.0, build-tools 36.0.0 and the Android 27 platform. Get tooling from [Android's SDK documentation](https://developer.android.com/tools) and [platform-tools downloads](https://developer.android.com/tools/releases/platform-tools).

The defaults refer to this workspace's ignored SDK downloads. Other users can supply normal SDK paths. Run from the repository root, adjusting these paths:

```powershell
$buildTools = "$env:LOCALAPPDATA/Android/Sdk/build-tools/36.0.0"
$androidJar = "$env:LOCALAPPDATA/Android/Sdk/platforms/android-27/android.jar"
./scripts/Build-SdProbe.ps1 `
  -BuildTools $buildTools -AndroidJar $androidJar `
  -Mode Probe -Output ./outputs/frameo-159k-sd-probe
```

Choose a new output path if one exists; the builder preserves earlier outputs. It builds a locally signed APK without DEX code, verifies identity and signature, creates a ZIP, and checks extracted-file SHA256 hashes. Signing material and intermediates stay under ignored `work/`, outside the package.

Extract the ZIP directly into the card root, preserving all names:

```text
SD root/
  Frameo_utilities/
    frameo_utilities.config
    [exactly one specially named diagnostic APK]
  p_frameo_jb
  README.txt
```

The config is `auto_run=action_update_version`. The default APK is package `net.frameo.frame`, versionCode `80322`, above the tested Frameo versionCode `80321`. Its filename is part of the command-injection mechanism: **never paste that filename into a terminal**. Keep exactly one APK inside `Frameo_utilities`. An unrelated Termux APK at the card root is outside that folder.

With Frameo running, open Settings and insert the card. Wait 20–30 seconds. A maintenance task may display an installation result and **Complete task**. Ours said **APK successfully installed**. That message alone does not prove that Termux, the dummy package or ADB was installed successfully. Read the script log.

On the PC, look for `frameo-159k-probe.txt` and `frameo-159k-probe.done` at the card root. The probe reads identity, selected properties, the existing `su` location and SELinux. It writes only its log and marker to the card; it does not execute `su` or change Android settings. Our log reported UID 0. No log means root execution has not been demonstrated.

The dummy APK uses a local signer different from installed Frameo. Android's normal signature check should reject its attempted replacement. The injected command runs before the installation result; the log is the evidence. Remove the trigger/package after the test and keep the log privately. Preserve the old log before deliberately clearing its marker for another test.

## 2. Establish the first authenticated ADB connection

Inspect the probe first. The ADB enabler requires UID 0, the exact model, platform, API, build and fingerprint above, and `ro.adb.secure=1`.

Use the **public** `adbkey.pub` belonging to the ADB instance you will connect from. Its usual Windows location is below. Never copy the private `adbkey` onto the card or into Git. If the public key is absent, initialize your own ADB setup before proceeding; do not borrow another person's key pair.

```powershell
./scripts/Build-SdProbe.ps1 `
  -BuildTools $buildTools -AndroidJar $androidJar `
  -Mode Adb -AdbPublicKey "$env:USERPROFILE/.android/adbkey.pub" `
  -Output ./outputs/frameo-159k-sd-adb
```

The builder validates the public key and uses a neutral comment. Before replacing a previous SD package, check its manifest and keep a local copy. Preserve diagnostic logs and other files; do not overwrite another maintenance package or an earlier attempt's baseline. Copy the new trigger config last, after the other files.

Insert the card while Settings is open. `scripts/sd-enable-adb.sh` saves existing authorization bytes and metadata, original TCP properties and adbd state in `frameo-159k-adb/` on the card. It preserves existing keys, adds your public key, sets key permissions, enables temporary TCP 5555, restarts adbd and checks the listener and authentication. It leaves the persistent TCP property unchanged at this stage.

On error it attempts rollback and records whether rollback was verified. Keep the state directory until the PC has confirmed access. The `started` marker blocks blind retries after interruption: inspect the result and baseline before doing anything with that marker. Successful execution retires the auto-run config so reinsertion does not automatically rerun the task.

Replace `FRAME_IP` with the frame's current IP:

```powershell
adb connect FRAME_IP:5555
adb devices -l
adb -s FRAME_IP:5555 shell id
adb -s FRAME_IP:5555 shell su -c id
adb -s FRAME_IP:5555 shell getprop ro.adb.secure
```

Our result was an authorized `device`, UID 2000 shell, UID 0 from `su`, and `ro.adb.secure=1`. Save only the precise SD state directory locally for recovery. Do not publish real authorization files or logs. This first connection alone does not prove reboot persistence.

## 3. Enable persistence with the stock firmware hook

The native property was discussed in issue #126. We verified this existing rule directly in this frame's `/init.rk30board.rc`:

```text
on property:persist.internet.adb.enable=1
    setprop service.adb.tcp.port 5555
    restart adbd
```

Before changing anything, record the original persistent and temporary port properties, native enable flag, authentication, current boot ID and authorized-key checksum. Keep the key backup from step 2. Both persistent properties were initially empty on our unit; temporary ADB already used 5555.

With a working authenticated, root-capable connection and the baseline saved:

```powershell
adb -s FRAME_IP:5555 push ./scripts/enable-native-adb-persistence.sh /data/local/tmp/frameo-enable-native-adb.sh
adb -s FRAME_IP:5555 shell "su -c 'chmod 700 /data/local/tmp/frameo-enable-native-adb.sh && sh /data/local/tmp/frameo-enable-native-adb.sh'"
```

The guarded script checks the exact firmware, UID 0, authentication and vendor hook, then sets:

```text
persist.adb.tcp.port=5555
persist.internet.adb.enable=1
```

The second property invokes the existing init trigger and may briefly disconnect ADB. Reconnect and read back both values, the current port and authentication. Verify that authorized-key bytes are unchanged. No init files or firmware images are edited, no startup service is added, and the script never reboots the frame.

## 4. Verify a complete power cycle

Record `adb -s FRAME_IP:5555 shell cat /proc/sys/kernel/random/boot_id` before shutdown. Shut down through the frame's menu, disconnect power, then power it on again. Reconnect and check:

```powershell
adb connect FRAME_IP:5555
adb -s FRAME_IP:5555 shell cat /proc/sys/kernel/random/boot_id
adb -s FRAME_IP:5555 shell getprop sys.boot_completed
adb -s FRAME_IP:5555 shell getprop persist.internet.adb.enable
adb -s FRAME_IP:5555 shell getprop persist.adb.tcp.port
adb -s FRAME_IP:5555 shell getprop service.adb.tcp.port
adb -s FRAME_IP:5555 shell getprop ro.adb.secure
adb -s FRAME_IP:5555 shell id
adb -s FRAME_IP:5555 shell su -c id
```

Our November 1 test used a complete shutdown and a different power adapter. The boot ID changed; boot completion was `1`; both ports were `5555`; the native flag was `1`; authentication stayed `1`; keys were unchanged; shell and root access worked. This establishes **one successful cold-boot test on this exact unit**, not every 159K or future firmware version.

The SD auto-run trigger had been retired. No Termux startup script, Termux:Boot, boot-image change or manual post-boot repair was used. Termux was briefly installed after the first ADB connection as a possible local terminal, then uninstalled. Authenticated ADB and root remained available after its removal.

## Rollback and recovery

Keep original probe logs, per-attempt SD snapshots and the native-persistence baseline privately. Investigate a failed rollback before another write.

For **our recorded baseline only**, the following clears both persistent values and restores the previous temporary port of 5555. It does not remove host keys. It is documented but has not been hardware-tested as a full restoration procedure:

```powershell
$target = 'FRAME_IP:5555'
$restore = 'setprop persist.internet.adb.enable ""; setprop persist.adb.tcp.port ""; setprop service.adb.tcp.port 5555; stop adbd; start adbd'
adb -s $target shell "su -c '$restore'"
```

Use your own baseline instead of assuming the original values were empty. Reconnect and verify every restored property. Restoring or removing an authorization file is a separate operation that must follow its actual saved baseline; no generic destructive key-reset command is provided.

## Tests and artifacts

```sh
bash tests/test-adb-enabler.sh
```

Ten host scenarios passed: preserving keys, one-shot success, empty keys, absent directory, rejecting another firmware, and rollback after listener, property or permission errors, including initially stopped adbd. Tests execute the production logic with isolated `work/` paths and mocked Android commands and Unix metadata. Hardware failure injection and full rollback remain untested.

Package builds check APK identity, API level, v1 signature, absence of DEX and ZIP extraction hashes. These checks are distinct from the hardware probe, authenticated connection, cold-boot test and post-Termux-removal checks that succeeded on the actual frame.

`work/`, `outputs/`, downloaded SDKs, generated packages, signing keys, real ADB keys and device logs are ignored by Git. The repository contains source and documentation, not a binary pre-authorized for someone else's device. No debloating has been performed as part of this report.
## Private pre-flash backups

`backup_frameo.py` and its companion `backup-device.sh` preserve application and OEM state from this exact firmware. They require an existing authenticated, root-capable ADB connection, Python 3.9 or newer, and at least 12 GiB of free local space. Use a new private output directory outside this public checkout:

```powershell
python ./scripts/backup_frameo.py `
  --adb "C:/path/to/platform-tools/adb.exe" `
  --target FRAME_IP:5555 `
  --exclude-photos `
  --output "C:/private-backups/frameo-159k-backup"
```

The collector reads every APK under system, vendor, OEM and installed-app paths, including the updated and factory Frameo copies. It saves package/UID/permission inventories, settings exports, init/fstab files, OEM configuration and Frameo vendor licensing files where present. A data-root archive preserves application data and configuration while excluding rebuildable caches, volatile logs, sockets/FIFOs and the temporary collection directory. Frameo is briefly force-stopped for that archive and its previous activity is reopened afterward.

`--exclude-photos` additionally excludes known personal photo/video, thumbnail and Frameo image-cache paths. Exact exclusions are recorded in the backup. App databases and preferences are retained and can still contain references to omitted media. Other data remains private even when photos are excluded.

The tool also reads compressed images of named recovery/firmware partitions. It does not image the large userdata or cache partitions and does not issue flash writes, reboot the frame, disable apps or change persistent ADB settings. APKs, metadata, compressed images and archives are staged in a new private root-owned directory under `/data/local/tmp`, granted read-only access for the authenticated ADB shell group, copied to the PC and compared against device-side SHA256 hashes. Verification checks APK ZIP CRCs, gzip integrity, tar listings, decompressed partition sizes/hashes, the presence of Frameo data, and media-path exclusions. Only after successful verification is the tool's own device staging removed. Failed attempts retain their staging for inspection.

**Backup output is private, local and unencrypted.** It can contain Wi-Fi credentials, application tokens, vendor licenses, account/device identities and other personal information. Never upload these files or vendor firmware to this public repository. The output directory includes an ignore-all `.gitignore`, but that is not a substitute for keeping it outside a public checkout.

This is a preservation backup, not an atomic live-system snapshot or a universally flashable image. A new OS can assign different app UIDs, require different SELinux labels, lack OEM libraries or privileged permissions, and reject hardware-bound credentials or licenses. Install compatible APKs first and restore app data selectively. Do not blindly extract all of `/data` or flash these unit-specific partition images onto another frame. A full restoration has not been tested.

If collection completed but transfer failed, use the same arguments and output directory with `--resume`. This checks the original ownership/completion markers and resumes transfer without stopping Frameo or recollecting its data. An incomplete device collection cannot be resumed this way.

An optional offline check uses `scripts/verify_private_backup.py` with `--backup`, `--aapt2` and a private `--scratch` directory. It writes an APK version/hash index, parses Frameo preference XML, and runs SQLite quick checks on isolated copies of its SQLite files. Realm data is preserved as bytes but not semantically validated with a Realm engine.

The documented frame yielded 56 APKs, including the current and factory Frameo versions, 14 named recovery/firmware images, and private application/OEM state. Device/PC hashes, APK ZIP checks, compressed-image hashes/lengths and tar listings passed. The photo-excluded archive contained no files in the documented personal-media paths. Additional offline checks parsed nine Frameo preference XML files and returned successful SQLite checks for three databases; two Realm files were retained without engine-level validation. No hardware restoration has been attempted.
