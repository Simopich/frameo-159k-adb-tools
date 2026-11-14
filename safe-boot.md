# Dashboard HOME and reversible stock startup suppression

## Scope and recorded configuration

This configuration uses Android's existing default HOME selection on the tested Frameo 159K, Android 8.1/API 27. It does not edit init scripts, firmware, boot partitions, authentication, or persistent ADB settings. Stock Frameo remains installed and enabled, with its existing data.

The later [global return gesture](https://github.com/Simopich/frameo-dashboard/blob/codex/implementation-plan/docs/GLOBAL_RETURN_GESTURE.md) adds an optional, owner-enabled accessibility handle to the configured Dev app. Hold the right-edge handle for 650 ms, drag left 64 dp, and release to invoke the existing default HOME. Its service requests no screen content or accessibility events. A separate controlled reboot verified automatic binding and return from Fulguris afterward; the HOME and stock boot configuration below were unchanged. The dashboard's **... > Global return gesture** page can hide the handle or disable the service completely.

The owner's configured dashboard is **Dev**, package `com.simopich.framedashboard.dev`, activity `com.simopich.framedashboard.MainActivity`. The separately installed Stable variant has a separate data store and demo configuration; it is not this unit's boot target.

The dashboard declares `MAIN`, `LAUNCHER`, `HOME`, and `DEFAULT` on its existing activity and uses `singleTask`. Repeated HOME presses reuse it. Back on the root HOME activity stays on the dashboard; Back during editing retains the existing discard confirmation. No new boot receiver, service, root startup task, or third-party autostart application is required.

The device also has Nova Launcher **8.0.18**, package `com.teslacoilsw.launcher`, activity `.NovaLauncher`, as a manually selectable fallback. Nova is a separate third-party launcher, not the custom dashboard or an open-source component of this repository.

Before selecting HOME, Android resolved it to `android/com.android.internal.app.ResolverActivity`; no default launcher was selected after Nova's installation. Stock Frameo's HOME activity is `net.frameo.frame/.ui.activities.AWaitForDeferredInitCompleted`. Its active boot receivers were `.core.BootCompleteReceiver` and `com.instacart.library.truetime.BootCompletedBroadcastReceiver`. The library receiver can start the stock application process even when its main startup receiver is disabled; this was confirmed in the first controlled reboot's ActivityManager log.

On November 14, 2026, the stock application automatically updated itself to **v1.32.18**, version code **80340**, during the browser tests. That update was separate from these changes. The historical firmware and ADB-enablement report in README describes the versions observed at that earlier test.

## Before making changes

Keep authenticated ADB connected on the trusted LAN. Verify shell and root access, `ro.adb.secure=1`, native ADB persistence, working dashboard and fallback activities, and the exact installed receiver names. Save current HOME resolution, package/component enabled states, boot ID, and private dashboard layout/connection preferences outside Git. This session's baseline is under ignored `work/safe-boot/` and includes private connection settings; do not publish it.

Prepare and inspect [the recovery script](scripts/Restore-FrameoHome.ps1) before changing HOME. Do not uninstall or clear stock Frameo or the dashboard. ADB recovery depends on the already verified native firmware hook, independently of the selected launcher.

## Applied commands

The Dev update is installed with `adb install -r` using its existing signing key, preserving preferences and layout. Replace `FRAME_IP` and the APK path as appropriate:

```powershell
adb -s FRAME_IP:5555 install -r PATH/TO/frame-dashboard-dev.apk
adb -s FRAME_IP:5555 shell am start -W -n com.teslacoilsw.launcher/.NovaLauncher
adb -s FRAME_IP:5555 shell cmd package set-home-activity --user 0 com.simopich.framedashboard.dev/com.simopich.framedashboard.MainActivity
adb -s FRAME_IP:5555 shell "su -c 'pm disable --user 0 net.frameo.frame/.core.BootCompleteReceiver'"
adb -s FRAME_IP:5555 shell "su -c 'pm disable --user 0 net.frameo.frame/com.instacart.library.truetime.BootCompletedBroadcastReceiver'"
adb -s FRAME_IP:5555 shell am force-stop net.frameo.frame
adb -s FRAME_IP:5555 shell am start -W -a android.intent.action.MAIN -c android.intent.category.HOME
```

Only the two active stock boot receivers are disabled, using the existing `su` because this privileged package rejects shell-only component changes. The stock HOME activity, other package components, Rockchip updater, Wi-Fi, system services, and the previous disabled-package baseline are retained. The existing WorkManager boot rescheduler was already inactive and was not changed. A force-stop ends stock background work already running in this session; it does not erase data. An explicit later launch of stock Frameo can restart its own background work and updates. Firmware/app updates can change component names or reset this behavior, so re-check after updates.

## Recover a usable HOME

These operations are available through authenticated ADB even if the dashboard UI fails. Restore stock Frameo as default HOME and reset both boot receivers to their manifest default states:

```powershell
./scripts/Restore-FrameoHome.ps1 -Adb 'C:/path/to/adb.exe' -Target FRAME_IP:5555
```

Alternatively, select Nova as the default and open it:

```powershell
./scripts/Restore-FrameoHome.ps1 -Adb 'C:/path/to/adb.exe' -Target FRAME_IP:5555 -Launcher Nova
```

Nova recovery leaves the stock boot receivers in their current state to avoid restarting stock on top of Nova. The script verifies the HOME selection and waits for its entry to reach persistent package restrictions before launching the recovery activity. This requires the existing root access. It never requests a reboot or clears data. It deliberately selects a usable HOME rather than reproducing the original launcher chooser. Neither recovery method removes or modifies dashboard settings.

For a temporary manual launch without changing HOME:

```powershell
adb -s FRAME_IP:5555 shell am start -n com.teslacoilsw.launcher/.NovaLauncher
adb -s FRAME_IP:5555 shell am start -n net.frameo.frame/.ui.activities.AWaitForDeferredInitCompleted
```

During an earlier stock fallback launch, the device issued a userspace-requested reboot before the first HOME selection had reached persistent storage. Its cause was not attributed; it followed the stock application's separate automatic update. Authenticated ADB recovered, and the dashboard preference hashes were intact. The final setup was then tested separately with controlled reboots. Nova is the preferred recovery route if stock behavior is uncertain. The complete Stock recovery branch was not executed because that would intentionally restart stock background work.

## Physical-device verification

The HOME-capable Dev update compiled and passed APK v2/v3 signature verification. In-place installation returned `Success`. Nova and stock activities were both launchable before the receiver changes. Repeated Home and Back on the root HOME screen kept the configured dashboard visible. The Nova recovery script was exercised, its default HOME verified, and the dashboard reselected.

Two controlled software reboots were performed. The first proved autonomous dashboard UI startup, but ActivityManager showed that the TrueTime receiver still started the stock process. After disabling that second boot-only receiver, the final reboot again opened the dashboard automatically, without any post-boot `am start` or repair. The boot ID changed and `sys.boot_completed=1`.

Passive samples through **185 seconds of uptime** retained the same final boot ID and dashboard foreground. No stock Frameo process or ActivityManager stock startup record was present during that final observation. No further unexpected reboot occurred in this bounded test; it does not establish indefinite uptime.

Authenticated Wi-Fi ADB reconnected; normal shell and existing root access worked. `ro.adb.secure=1`, `persist.internet.adb.enable=1`, and both ADB port properties remained `5555`. Stock Frameo remained installed, enabled, and launchable by its retained activity, with exactly the two documented disabled receiver overrides. The previously disabled package list remained only `com.android.nfc` and `com.android.systemui`; this setup did not change those existing states.

The private dashboard layout and connection-preference SHA-256 hashes matched the pre-install baseline after both controlled reboots. Screenshots showed the owner's configured calendar/weather layout rather than Stable's demo. Private screenshots, preference copies and diagnostic logs remain under ignored `work/safe-boot/`.

The November 1 cold-boot result in README concerns ADB persistence. The later dashboard checks use software reboots and do not establish a new complete power-cycle test.
