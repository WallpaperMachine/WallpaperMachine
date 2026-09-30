# Verification log

Append-only history of what was actually verified, when, and with what result.
The newest entry goes on top; never rewrite an older entry to match today's
tree. Every entry is evidence about the tree it was taken on, not about the
current one — re-run the relevant checks after integration and add a new entry
instead of reusing an old result. Durable guidance belongs in the sibling docs:
test layers and policy in [README.md](README.md), renderer commands and
regression areas in [renderer.md](renderer.md), manual checks in
[manual-smoke.md](manual-smoke.md). Result bundles and probe output are local
and disposable, so entries state counts and commands rather than artifact
paths.

Entry format, so the log stays skimmable: a one-line summary heading, one short
paragraph of context only when the result needs it, then a bullet per command
with its exit status, counts and any skip. Keep an entry around ten lines. A
fact that will still matter next week is not an entry — promote it to the doc
that owns it (renderer behaviour and known-failing tests to
[renderer.md](renderer.md), build and signing traps to
[../build.md](../build.md)) and cite it from there.

Retention: this file keeps the ten newest entries. When it grows past that,
move the oldest entries verbatim into
[archive/verification-log-2026-09.md](archive/verification-log-2026-09.md)
(or a new dated archive file) first, and promote anything durable before it
goes. Trimming is allowed; editing an entry's recorded result is not.

## 2026-10-01 — Lock-screen extension mismatch diagnostics

- Added revision-scoped extension identity, schema-version and configuration-load diagnostics; legacy extension copies are identified by running bundle path after readiness timeout.
- python3 scripts/test.py --only LockScreenExtensionDiagnosticsTests --only LockScreenWallpaperServiceTests: exit 0; 31 passed before the final screen-saver monitor regression was added.
- python3 scripts/test.py: exit 0; all 226 Python tests passed; native gate 898 passed, 0 failed, 11 skipped of 909. Includes all 10 new diagnostic regressions.
- Native skips: nine opt-in media/device tests and two live Workshop network tests. No asset-dependent renderer checks were run; renderer and bridge were unchanged by this task.
- Covered incompatible schema before scene decoding, missing/malformed configuration, stale revisions, same-bundle symlinks, configuration success without frame readiness, failed diagnostic writes, legacy timeout restoration and later screen-saver configuration failure.
- git diff --check: exit 0. XcodeGen regenerated the project through test.py; native localization checks passed in the gate.
- python3 scripts/clean.py --dry-run: exit 0; broad cleanup deferred to preserve the shared workspace renderer evidence under artifacts.
- No Release rebuild, app restart, registration changes or desktop tests. Live extension selection and lock-screen visuals remain unverified.

## 2026-09-30 — Restore per-display screen saver precedence

- Read-only inspection on macOS 26.6.2 found AllSpacesAndDisplays.Type=idle with Provider=default despite WallpaperMachine being selected for each display.
- Native WallpaperAgent type metadata confirms an optional global selection and separate idle, desktop, individual and linked cases; no live store was changed.
- python3 scripts/test.py --only LockScreenWallpaperTests: exit 0; 34 passed, 0 failed, 0 skipped.
- python3 scripts/test.py --only LockScreenWallpaperServiceTests: exit 0; 22 passed, 0 failed, 0 skipped.
- python3 scripts/test.py: exit 0; all Python modules passed; native suite 888 passed, 0 failed, 11 skipped (9 opt-in media tests and 2 live Workshop tests).
- Isolated regressions cover global Idle removal, combined global choices, disable and crash recovery, reload failure, independent lock-screen operation and later System Settings edits.
- git diff --check and owning-document local link checks passed. No Release build, installation, restart or desktop run; real idle playback and visual behavior remain unverified.

## 2026-09-30 — Import picker follows live app language

- python3 scripts/test.py --only WallpaperImportPickerTests: 5 passed, 0 failed; child cancellation/reaping, activation failure cleanup, invalid handshake and failed exit.
- python3 scripts/test.py: all 17 Python modules passed; native gate 883 passed, 0 failed, 11 skipped of 894. Skips: 9 opt-in native-video media cases and 2 live Workshop network cases.
- Authorized signed smoke app compiled the production picker/helper sources: English parent opened Japanese helper, selected one image and received its URL; isPresenting was false after return. No import or wallpaper change performed.
- Native helper cancellation returned no URLs; parent-pipe EOF before activation returned null and exited 0 without showing a picker.
- Changed WebUI copy detector returned no findings; catalog parity and offscreen panel language tests passed in the gate.
- No Release build or main-app desktop launch. Full real-app import, focus across Spaces and native picker visuals in every language were not exercised. Prior research covered all four native launch languages.

## 2026-09-30 — Perspective wallpaper fix delivered after gate recovery

- The earlier app-gate blocker is cleared. Concurrent screensaver fixes were preserved: canonical asset URLs, denied-or-unavailable capture behavior and rendered content checks; this delivery added no changes to those files.
- python3 scripts/test.py --serial — exit 0; all 17 Python modules passed; native 883 passed, 0 failed, 11 explicit opt-in skips of 894. Serial execution avoided the previous multi-runner launchd spawn failure without excluding tests.
- python3 scripts/check_renderer.py — exit 0; all renderer executables passed, all 10 generated pooled/isolated images equal with zero diagnostics, eight projects reloaded twice. Local-asset skips remain explicit.
- Fresh surface-free Native Metal scenario: installed perspective wallpaper drew 1200 frames at 3840x2160; inspected the private final frame for full coverage, live clock/date/status and faded login overlays. 44 render passes/frame, 1 blit/frame, 0.53 ms thread CPU per drawFrame; no desktop FPS or power claim.
- CARGO_BUILD_JOBS=4 CMAKE_BUILD_PARALLEL_LEVEL=4 python3 scripts/build.py --configuration Release — exit 0; rebuilt the full Rust/C++ renderer, regenerated bindings and built the Release application.
- Delivered build/Build/Products/Release/WallpaperMachine.app. codesign --verify --deep --strict passed; diff -qr confirmed bundled Contents/Resources/WebUI matches WebUI byte for byte.
- No app launch/restart, desktop input, wallpaper changes or live audio capture. The user must quit the old app and open the delivered build; physical desktop behavior and exact Windows visual parity remain unverified.

## 2026-09-30 — Independent native wallpaper screen saver

- `python3 scripts/test.py --serial` — exit 0; all 17 Python modules passed; native 883 passed, 0 failed, 11 skipped (9 opt-in media/device and 2 live Steam checks).
- `cargo test --release -p wallpaper-bridge --lib` with scripts/build.py cargo environment — exit 0; 361 passed.
- `python3 scripts/check_renderer.py` — exit 0; generated pooled/isolated pixels equal, no diagnostics; eight-project reload cycles passed. Private wallpaper corpus not exercised.
- Offscreen native CAContext/WebKit smoke — rendered expected pixels, advanced canvas frames, preserved committed properties and paused/resumed; no window ordered or live selection changed.
- Isolated settings browser smoke — screen-saver toggle left lock-screen toggle unchanged; busy state disabled the control. Impeccable detector returned no findings.
- Isolated regressions cover independent selection/restoration, topology gaps, native-video exports, web properties/files, capture denial, readiness and paused teardown.
- Real idle transitions, lock/password UI, multi-monitor compositor delivery and sleep/wake visuals remain unverified. No Release app rebuild, activation or restart.
- The shared workspace contained unrelated import-picker and renderer changes; those are excluded from this feature commit.

## 2026-09-30 — Perspective scene rendering and live text compatibility

- Renderer gate: python3 scripts/check_renderer.py passed; 494 tests across 23 binaries, 3 explicit local-asset skips; all 10 generated pooled/isolated pixel cases equal with zero diagnostics; 8 projects reloaded twice.
- Focused suites passed: text_object_runtime_test 60, script_runtime_compat_test 81, scene_schema_tests 89, mdl_schema_tests 55; the final renderer gate also passed 19 layer-reference and 10 render-scale tests.
- Installed perspective scene: both Native Metal and Compatibility drew 1200 frames offscreen at 3840x2160. Inspected final private images: no black quadrant or login overlay, current clock/date/status text, full-resolution starfield and visible star glows. No asset edits or wallpaper-specific renderer branches.
- Native Metal final scenario: 44 render passes/frame, 26 on scene output, 1 blit/frame, 0.52 ms thread CPU per drawFrame; 299270656 render-target bytes and 779829248 device-allocated bytes. These exclude script/update CPU and do not establish desktop FPS or power use.
- Compatibility final scenario: 738564736 VMA allocated bytes; process footprint/peak 2156971808 bytes. Native resolution and retained perspective source mips use more resources than a blurred 1080p/down-mip path; no supersampling or per-frame text-style raster uploads.
- Routine application gate: python3 scripts/test.py failed, 879 passed / 4 failed / 11 skipped. Three assertions belong to concurrently added ScreenSaverWebSurfaceTests (capture error type, owned-file URL, live-canvas color); another failure is test-runner launchd spawn. Those files and other concurrent app/bridge/extension edits were left unchanged.
- No Release rebuild, app launch/restart, desktop input or wallpaper changes. Initial diagnostic helpers unexpectedly initialized sound devices on asset mount despite their no-Play comments; corpus helpers now explicitly use the null backend. No live-audio or desktop verification claimed.
- No commit: the required shared application gate is failing. Exact Windows parity, physical desktop presentation and battery/power effects remain unverified.

## 2026-09-30 — Issue #17 non-disruptive visual verification

- User authorized visual verification and chose to keep the run non-disruptive rather than switch macOS Spaces.
- python3 scripts/test.py --only Issue17VisualSmokeTests: temporary harness passed, 1 test, 0 failures, 0 skips; actual bundled WKWebView hosted by SwiftUI in the production ControlPanelWindow. Harness removed after capture.
- Inspected 8 WKWebView snapshots: light/dark × windowed 760×560, full-screen layout 1920×1080, half-screen layout 960×1080, and restored windowed 760×560. All four navigation tabs remained visible.
- Applied the production full-screen layout offscreen beneath an opaque native title bar; did not set the native full-screen style bit or call toggleFullScreen. Web content stayed inside the unobscured native bounds, with 32 successful native tab hit-tests and unchanged window frames.
- Traffic-light inset restored to 79 points in windowed mode and cleared to 0 in the full-screen layout. Installed → Settings click-through succeeded. Foreground application PID was unchanged and the verification window was never shown.
- Hidden native cacheDisplay captures contained stale WebKit frames and were discarded; visual inspection used WKWebView.takeSnapshot instead. Guidance recorded in docs/development-tools.md.
- Peekaboo reported Screen Recording and Accessibility unavailable. No permissions requested, no desktop input, no Space switch, no existing app restart, and no wallpaper changes. Live full-screen/Split View transitions remain unverified by user choice.
- Only the Debug test host was compiled. No Release rebuild; the running Release app and its bundle were left untouched. Local screenshots remain disposable and uncommitted.

## 2026-09-30 — Energy readout hierarchy and measurement disclosure

- python3 scripts/test.py — exit 0; Python suites passed; native 853 passed, 0 failed, 11 skipped (9 opt-in media, 2 live Workshop). The shared tree includes unrelated concurrent window-sizing changes.
- Headless Chromium on the real WebUI: 249 state/theme/language/layout cases passed at 1100px and the native 760px minimum, plus an isolated 360px settings container; no energy-card overflow. Tested text contrast stayed at least 5.33:1 across light/dark and neutral/warm/cool tones.
- Space/Enter disclosure operation passed; open state and focus survived energy pushes and snapshots, and updates preserved focus on the quality slider. Measuring, unavailable, GPU contention, battery omission, watt units, zero values and before/after comparisons exercised.
- Impeccable mechanical detector on settings.js and settings.css — exit 0, no findings.
- No screenshots, desktop interaction or native visual review; power sampling behavior unchanged. No Release rebuild or app restart.

## 2026-09-30 — Control-panel full-screen navigation (#17)

- python3 scripts/test.py --only ControlPanelWindowSizingTests: 2 passed, 0 failed, 0 skipped.
- Temporary offscreen AppKit smoke executable: opaque title-bar chrome intercepted navigation before the layout change; the fixed layout and restored windowed layout both delivered hits to content and preserved the window frame.
- Regression coverage exercises 1920×1080, 960×1080 and 760×560 bounds, unobscured content, navigation hit-testing and restoration of the unified title-bar layout.
- python3 scripts/test.py: all 17 Python test modules passed; native gate 853 passed, 0 failed, 11 skipped of 864.
- Skipped: 9 opt-in NativeVideoPlayerMediaTests and 2 live-network WorkshopTests; no asset-dependent skips.
- Live full-screen and Split View transitions and visual presentation remain unverified; no window was shown or Space transition requested.
- Release app not rebuilt; the running app remains unchanged. Unrelated concurrent WebUI and documentation edits were preserved.

## 2026-09-30 — Keep the active-display filter on one line

- Offscreen WKWebView smoke — exit 0; 24 cases across 760, 840, 841, 1040, 1041 and 1280px in English, Japanese, Simplified Chinese and Traditional Chinese. The full label occupies one line without overflow; checking and clearing Active filters the expected wallpapers. Discover widths and collapsed layout remain unchanged. Throwaway probe removed.
- `python3 scripts/test.py` — first pass failed: 850 passed, 2 failed, 11 skipped. The broad sidebar sizing rule changed Discover width; it is now scoped to the Active row. The other failure was the documented WebKit InvalidTransition/deinit error.
- `python3 scripts/test.py --serial` — exit 0; 852 passed, 0 failed, 11 skipped of 863; all Python script modules passed. Skips cover opt-in native media and live Workshop checks.
- Mechanical UI scan returned no findings. No desktop screenshots or visual run; no Release rebuild.
