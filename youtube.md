# Lightweight YouTube client

LibreTube 32.1 was installed and tested on the Android 8.1 / API 27 Frameo 159K on November 14, 2026. It runs without Google Play Services or a Google account.

## Selection

The current stable releases considered were [LibreTube 32.1](https://github.com/libre-tube/LibreTube/releases/tag/v32.1) and [NewPipe 0.29.3](https://github.com/TeamNewPipe/NewPipe/releases/tag/v0.29.3). Both are maintained open-source clients. LibreTube's official APK is 9,253,519 bytes (8.82 MiB), versus NewPipe's 16,980,865 bytes (16.19 MiB). LibreTube was selected for its smaller download, Android compatibility, and successful playback on this unit. APK size is not a comparative RAM or performance benchmark.

LibreTube 32.1 supports YouTube's SABR streaming protocol. Its [release build configuration](https://github.com/libre-tube/LibreTube/blob/v32.1/app/build.gradle.kts) requires API 26 or newer, compatible with this frame's API 27. The [project](https://libretube.dev/) is licensed under GPL-3.0-or-later, as specified in its [README](https://github.com/libre-tube/LibreTube/blob/v32.1/README.md).

## Installed package and verification

- Package: `com.github.libretube`
- Version: `32.1`, versionCode `72`
- Minimum SDK: `26`; target SDK: `36`
- APK: [official GitHub release asset](https://github.com/libre-tube/LibreTube/releases/download/v32.1/app-release.apk)
- APK SHA-256: `437dbb55540ac573f864938fc3595f69fc13df5d568b237aded9935559fe1353`
- Signer certificate SHA-256: `720c4fcecf738a41d033b9fbe0bef97ac232030ce93e274d2e0ae232e44eeace`

The downloaded hash matched the official GitHub API release-asset digest. Android SDK `apksigner` verified APK v2 and v3 signatures. This establishes download integrity and a valid APK signature; it is not an independent source-code audit. ADB installation returned `Success`; the installed package reported the expected version and SDK levels.

## Actual-device tests

The default home feed loaded. Searching for `Big Buck Bunny Blender` returned video results and thumbnails. Selecting **Big Buck Bunny** from **Blender** displayed actual animation frames and played for approximately 59 seconds. Android's media session reported `PLAYING`, speed `1.0`, positions increasing from `2855` to `18451` milliseconds, and `error=null`. Pausing reported `PAUSED`, position `58911`, with `103916` milliseconds buffered. The fullscreen player rendered at `1920x1080`.

A paused-player memory sample reported total PSS of 128,342 KiB, plus 1,218 KiB swap PSS. This is one observation, not a peak-memory measurement or a comparison against NewPipe. Speaker audibility and sustained playback were not independently measured. No account or Piped instance was configured. NewPipe was downloaded as a verified fallback but was not installed because LibreTube passed.

LibreTube was force-stopped after testing; playback ended. No launcher, boot configuration, vendor package, root setting, or Android system setting was changed by this installation. APKs, release metadata, UI dumps and screenshots remain in ignored `work/youtube-install/`; temporary device-side test files were removed.

YouTube can change its interfaces or restrict anonymous playback. This successful test does not guarantee every video, resolution, live stream, or future release. Update from the same official signing channel if playback later breaks.
