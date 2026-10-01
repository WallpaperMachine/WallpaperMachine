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

## 2026-10-01 — Support the macOS linked default wallpaper

- Updated native selection to accept the built-in linked default, suppress only requested global Desktop/Idle overrides, and restore linked or inherited originals while preserving external edits.
- Focused LockScreenWallpaperTests and LockScreenWallpaperServiceTests: 69 passed after fixing metadata restoration; the added legacy-journal case also passed in the full gate.
- python3 scripts/test.py: passed; 226 Python tests and 918 native tests passed, 0 failed, 11 skipped (9 opt-in native-media tests and 2 live Workshop tests).
- python3 scripts/build.py --swift-only --configuration Release: passed; delivered the updated Release app.
- codesign --verify --deep --strict on the Release app: passed.
- Under existing user approval, unregistered the Debug extension produced by testing and registered Release; pluginkit listed only the Release extension afterward.
- Regression fixtures cover both activation orders, partial disable, crash/reload recovery, copied fallbacks, external choices and metadata, and legacy global journals.
- Live lock-screen/screen-saver rendering, idle transitions, sleep/wake, and quit restoration remain unverified; no desktop control or wallpaper changes were performed.

## 2026-10-01 — Wait for native-provider and desktop-poster restoration on quit

- python3 scripts/test.py --only DesktopWallpaperTests --only LockScreenWallpaperServiceTests — exit 0; 64 passed, 0 failed, 0 skipped.
- python3 scripts/test.py — exit 0; 226 Python tests passed; 910 native tests passed, 0 failed, 11 skipped of 921.
- Skipped: nine opt-in NativeVideoPlayerMediaTests and two live WorkshopTests. Renderer code unchanged; no renderer corpus checks.
- Fixtures cover persisted posters temporarily invisible during native reload, delayed original persistence, retained journals, failed quit with retry, external choices during the wait, and ordered Desktop/Idle plus poster restoration.
- python3 scripts/build.py --swift-only --configuration Release — exit 0; Release app built. codesign --verify --deep --strict — exit 0.
- git diff --check — exit 0. Read-only logs showed rejected desktop writes and extension copies loaded from installed and Debug apps. No live wallpaper changes, application restarts, or extension registration changes were performed.
- Visual desktop restoration with an active native provider remains unverified; the separate extension-copy conflict remains unresolved.

## 2026-10-01 — Preserve recoverable originals before desktop poster writes

- python3 scripts/test.py --only DesktopWallpaperTests — exit 0; 32 passed, 0 failed, 0 skipped.
- python3 scripts/test.py — exit 0; 226 Python tests passed; 904 native tests passed, 0 failed, 11 skipped of 915.
- Skipped: nine opt-in NativeVideoPlayerMediaTests and two live WorkshopTests; no renderer changes or renderer corpus checks.
- Regression fixtures cover effective wallpaper capture before any write, independent display and Space originals, refusal to replace unresolved originals, and repair/relaunch recovery of legacy empty journals even with unchanged frames.
- Read-only inspection confirmed empty inherited originals in the existing desktop journal; no wallpaper settings were modified. Such journals need a fresh user selection when no original survives.
- git diff --check — exit 0. Desktop appearance and actual macOS restoration remain unverified; no desktop control or Release rebuild.

## 2026-10-01 — Welcome guide Wallpaper Engine ownership check

- python3 scripts/test.py --only DownloaderLifecycleTests — exit 0; 24 passed, 0 failed, 0 skipped. Covers owned, missing and unknown license responses, complete app IDs, session reset and no downloads during sign-in.
- python3 scripts/test.py --only ControlPanelShellTests/testWelcomeOwnershipNoticeAllowsContinuingAndRecheckingAfterPurchase — exit 0; 1 passed. Offscreen guide covers purchase links, unconfirmed results, continuing setup and rechecking after purchase.
- python3 scripts/test.py — exit 0; 226 Python tests passed; native gate 901 passed, 0 failed, 11 skipped of 912. Skips: 9 opt-in media tests and 2 live Workshop tests.
- Impeccable detector on WebUI/welcome.js — exit 0; no findings. git diff --check — exit 0. Added strings cover all shipped languages.
- Live Steam authentication and license responses, desktop presentation and visual appearance remain unverified; synthetic PTY fixtures and offscreen WebKit only. Release app not rebuilt.
- python3 scripts/clean.py --dry-run — exit 0; existing shared artifacts retained to avoid removing unrelated evidence.

## 2026-10-01 — Bounded HDR and interactive scene compatibility

- User selected a general bounded bloom model rather than claiming exact proprietary Wallpaper Engine HDR parameter parity. No wallpaper-specific rendering branches or private asset edits.
- cargo test --release -p shader --features ffi with the build cargo environment: exit 0; 522 passed. Fourth-channel metadata and disabled-slot behavior covered.
- Targeted CMake build and text/script/mouse/scene/texture suites: exit 0; 60, 84, 13, 89 and 22 passed respectively; two opt-in local text cases skipped. Particle suite: 41 passed. Diagnostic dumper library compiled.
- GPU HDR filters: four passed, including real TEX bit23 emissive radiance through effects/linked layers, SDR preservation, missing-source rejection, bounded spread, live strength changes and zero halo strength.
- Installed perspective scene: both Metal and Compatibility completed 1200/2400 frames at 1/60 and 1/120 simulation steps, 1680x1050, synthetic clock click/hover entry/exit and broadband audio. Sampled script errors zero; menu and overlay transitions, moving bars/waves and numeric readouts verified.
- Full-resolution scenarios: Native Metal 1200 frames and Compatibility 2400 frames at 3840x2160 completed; sampled input transitions and script errors passed. Offscreen frames visually inspected; no desktop capture or audio hardware used.
- Native drawFrame CPU means: 0.60 ms at 1680x1050, 0.59 ms at 3840x2160. These exclude script tick/GPU/display cadence and are not FPS or power claims; HDR half-float target cost is documented, with no forced supersampling.
- python3 scripts/test.py --serial: exit 0; all 17 Python modules passed; native 883 passed, zero failed, 11 opt-in skips of 894.
- python3 scripts/check_renderer.py: isolated final run exit 0; all renderer executables passed, ten generated pooled/isolated comparisons equal with zero diagnostics, eight projects reloaded twice. Three default opt-in asset checks skipped; target scene exercised separately. Earlier concurrent run failed one baseline video-frame timing assertion; retained assertion passed on the isolated full rerun.
- Documentation links and provenance JSON checked. No Release app rebuild, launch/restart, live settings changes or desktop input. Exact Windows visual equivalence, physical presentation cadence and power effects remain unverified.

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
