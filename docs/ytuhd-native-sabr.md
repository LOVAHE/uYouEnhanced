# YTUHD Native/SABR Fix2

Target: YouTube 21.36.6 with YouMod 2.0.0, sideloaded on iOS 27.

## Evidence

The NativeVP9 Fix1 package stopped the previously observed code-page crash. That did not establish playback compatibility. A subsequent test reproduced a playback error with YTUHD enabled and restored playback with YTUHD disabled. The intervening audio-track timing patch did not resolve it.

The legacy Tonwalter implementation unconditionally overrides server ABR flags while enabled. It also changes private ABR filtering state and manually supplies raw HLS playlist entries. Its separate FixPlayback module replaces the player factory and drops high-resolution formats. These paths are verified in the source, but the exact failing subpath is not proven without the original playback NSError or a trace.

## Change

The new YTUHD component compiles NativeSafe.xm, Settings.x and the manual-reload part of ReloadVideo.x. It does not compile the legacy Tweak.xm, FixPlayback.x or Filter.x.

NativeSafe preserves the current player, server ABR, native codec-support checks, native format fallback, and manifest handling. It raises existing positive VP9/AV1 maxArea and maxFps limits toward 3840x2160 and 60fps. Zero stays zero; higher existing limits are not lowered. Raising a limit does not guarantee a video supplies that format or that the device can decode it. HDR filtering, when requested, retains the original list rather than yielding an empty list.

YTUHD no longer contains SupportsCodec pattern hooks, libundirect, native function patching, OS spoofing, forced AVPlayer construction, or automatic buffering-reload loops. Other bundled tweaks are untouched. Legacy software-decoder controls are not exposed in this native-only component. Manual reload remains available.

The settings page exposes local playback diagnostics: build ID, enabled state, filter invocation/update counters, hardware capability hints, and the last NSError domain/code chain. It does not collect video URLs, cookies or authentication tokens, and does not upload diagnostics.

## Build and artifact

- Patch generator: `Tweaks/ytuhd_native_safe.py`
- Workflow: `.github/workflows/build-ytuhd-native-safe.yml`
- Source/build commit: `a9cd0bc507fae8bfe05fec31039858ddd773205a`
- Actions run: `35876770580`
- Component artifact: `10759305436`
- YTUHD package version: `1.13.4+nativevp9.2`
- Built YTUHD binary SHA-256: `443c7ada04adeeadddc1de741f75b3b0dfae229e971122cfa3c9cbe0980cb343`

The workflow pins Theos, Logos, SDK and header revisions. It builds open-source components only; no YouTube IPA is uploaded to GitHub.

The final IPA is assembled by replacing only `Payload/YouTube.app/Frameworks/YTUHD.dylib` in the AudioFix1 IPA. All 12,248 remaining ZIP entries have identical content. There are no added or removed entries, and the main executable and every other tweak are unchanged.

Final IPA: `YouTube_21.36.6_YouMod-2.0.0_Full-NativeSABR-Fix2.ipa`

SHA-256: `d26da65665c8abf1ac88876ee999a2b1bec82c3987e31a06b9f90a61d6e856a4`

## Validation status

Compilation, 46 shared C policy cases, source/binary exclusion checks, package dependency checks, ZIP integrity, and 44 YTUHD CodeDirectory hash slots passed. These are not physical-device playback tests. Final signing remains the responsibility of the sideloading tool.

Device acceptance remains pending. Import and re-sign the new IPA, check the settings title `YTUHD Native/SABR Fix2`, turn on `Native 2K/4K (SABR compatible)`, select `Automatic (VP9 + AV1)`, then restart the app. The previous disabled preference is preserved and must not be mistaken for a successful enabled-path test. Check the previously failing video first, followed by available 1440p/2160p formats, seeking, audio selection and PiP. If playback fails, copy diagnostics before restarting the process.
