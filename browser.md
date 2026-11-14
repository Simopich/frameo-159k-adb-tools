# Lightweight open-source browser

## Selection and provenance

Fulguris **2.1.2**, version code **265**, is the selected browser for this Android 8.1 frame. The F-Droid build is **9,359,352 bytes (8.93 MiB)** and requires Android 5.0/API 21 or newer. The APK has no native libraries, so it does not require a particular CPU ABI. Its package is `net.slions.fulguris.full.fdroid`.

The project is open source under the Mozilla Public License 2.0. Its F-Droid variant excludes the optional Firebase statistics/crash-reporting component used by the other release channels. It uses the installed Android WebView rather than bundling a second large rendering engine. The October 15, 2026 release includes fixes for older-device downloads and startup crashes.

FOSS Browser was also considered. Its latest release, version 24, requires Android 10. Its compatible version 23 is smaller, but Fulguris retains Android 5.0 support in the current release and offers a landscape tab bar and keyboard support suited to this frame.

Primary sources checked November 14, 2026:

- [Fulguris source and release-channel description](https://github.com/Slion/Fulguris)
- [F-Droid package, license, compatibility and release metadata](https://f-droid.org/en/packages/net.slions.fulguris.full.fdroid/)
- [Exact official F-Droid APK](https://f-droid.org/repo/net.slions.fulguris.full.fdroid_265.apk)
- [F-Droid repository index](https://f-droid.org/repo/index-v2.json)
- [FOSS Browser package and minimum Android versions](https://f-droid.org/packages/de.baumann.browser/)

The download's SHA-256 matches F-Droid repository metadata:

```text
72a95ef9111837e6a557cefac53744e9a8b4f8413fce199e485e249d04c886cc
```

Android `apksigner` verified the v1, v2 and v3 signatures. The signer certificate SHA-256 matches the F-Droid metadata:

```text
66958f3366388c23ca1a3cbfd91545cca4abf3e79edaab4fe988213e392b07a1
```

APK and repository-index downloads remain in ignored `work/browser-install/`. No binaries are tracked.

## Installation

Installation through authenticated ADB returned `Success`. Android's installed-package inventory confirms version `2.1.2`, version code `265`, minimum API `21`, and enabled installation for user 0. The launcher activity is `fulguris.activity.SplashActivity`.

## Device verification

First-run onboarding was completed. The browser then successfully rendered `https://example.com/` through its address bar. Following the page's **Learn more** link rendered IANA's **Example Domains** page. The browser Back button restored Example Domain, confirmed through the actual Android UI hierarchy. No certificate exception or TLS bypass was used. These checks verify installation, landscape rendering, touchscreen navigation and working HTTPS on the existing engine; they do not claim universal site compatibility.

Local screenshots and the final UI dump remain in ignored `work/browser-install/`. Temporary screenshot/UI-dump files created on the frame for this test were removed. The main browser process reported `115061 kB` PSS after this small test; separate WebView renderer processes are not included, so this is not a total browser-memory benchmark. The small APK describes download/storage cost, not all runtime memory use.

## Rendering engine and limitations

The frame's active provider is `com.android.webview` **113.0.5672.136**. `dumpsys webviewupdate` reports it valid, enabled for all users, and preferred. Installing a small WebView browser does not update this engine. Its age limits modern-site compatibility and security; successful test pages do not establish safety for sensitive accounts. No WebView replacement, HOME selection, boot setting, root setting or firmware change is part of the browser installation.

The browser was sideloaded from the official F-Droid APK. It will not receive automatic update notifications unless an updater is configured later.
