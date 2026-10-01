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

## 2026-10-01 — PR 21 recovery journal review fix

- CodeRabbit: cancelled-quit synchronization and verification status findings were already addressed in 69fad27; fixed the remaining linked/inherited journal decoding finding.
- New linked and inherited baseline regressions reproduced both silent failures before the fix (targeted run exit 65); malformed arrays and invalid plist bytes now preserve the store and journal, skip reload, and recover after repair.
- python3 scripts/test.py --only LockScreenWallpaperTests: exit 0; 46 passed, 0 failed, 0 skipped.
- python3 scripts/test.py: exit 0; 226 Python tests and 1,031 native tests passed; 11 skipped (9 optional media and 2 live Workshop tests).
- python3 scripts/build.py --swift-only --configuration Release: exit 0; built the Release app containing the fix.
- Initial verification needed a test-fixture type annotation; sandboxed Xcode test-runner and compiler-plugin failures were resolved by rerunning with approved access outside the sandbox.
- git diff --check: exit 0. No renderer or generated-binding changes; desktop and visual behavior remain unverified. No app launch, install, restart, wallpaper change or live account access.

## 2026-10-01 — PR 21 cancelled-quit poster recovery

- Fixed the Codex review finding: a cancelled quit restarts desktop poster synchronization immediately when native desktop ownership has been released; an owned provider remains protected.
- python3 scripts/test.py --only DesktopWallpaperTests --only LockScreenWallpaperServiceTests: exit 0; 65 passed, 0 failed, 0 skipped. The initial sandboxed attempt failed before tests because Xcode could not launch its Swift macro compiler; the permitted unsandboxed rerun passed.
- python3 scripts/test.py: exit 0; 226 Python tests and 1029 native tests passed, 0 failed; 11 optional cases skipped (9 media, 2 live Workshop).
- python3 scripts/build.py --swift-only --configuration Release: exit 0; built the Release app after the gate.
- git diff --check: exit 0. No renderer or generated-binding changes.
- The real AppKit cancelled-quit flow and visual desktop behavior were not exercised; no desktop control, app launch, install, or restart.

## 2026-10-01 — Integrate wallpaper recovery and Steam ownership fixes with main

- Merged the latest remote main without rewriting the five local feature/fix commits; preserved both branches of verification history while resolving log conflicts.
- python3 scripts/build.py --renderer-only --configuration Release: passed; regenerated the renderer bindings required by the incoming main branch.
- python3 scripts/test.py: passed; 226 Python and 1,029 native tests passed, 0 failed, 11 skipped (9 opt-in media and 2 live Workshop tests).
- python3 scripts/check_renderer.py: passed; all renderer binaries exited 0, all 10 synthetic scenes matched between pooled and isolated runs with no diagnostics, and 8 projects passed two reload cycles.
- Renderer asset-dependent checks skipped: the two private text-scene regressions and the environment-selected native Metal project corpus. Authored visual compatibility was not established.
- python3 scripts/build.py --configuration Release: passed; strict deep codesign verification passed.
- Under prior authorization, removed the test-generated Debug extension registration and registered the rebuilt Release copy; pluginkit listed only Release.
- The user confirmed the preceding wallpaper fix works. Live desktop, lock-screen, saver, and quit behavior of the merged build were not retested; no automatic app restart was performed.

## 2026-10-01 — Keep inherited native display choices complete

- Read-only WallpaperAgent logs identified DecodingError.keyNotFound for Idle in a synthesized Space display override; macOS rejected the entire Index before launching the extension. Enabling both modes filled the missing field and succeeded.
- Synthesized individual display nodes now resolve and journal both inherited choices, preserve the inactive mode, and return to inheritance on disable/recovery unless an external edit must survive.
- python3 scripts/test.py --only LockScreenWallpaperTests --only LockScreenWallpaperServiceTests: 73 passed, 0 failed.
- python3 scripts/test.py: passed; 226 Python and 921 native tests passed, 0 failed, 11 skipped (9 opt-in media and 2 live Workshop tests).
- python3 scripts/build.py --swift-only --configuration Release: passed; codesign --verify --deep --strict also passed.
- Under existing user authorization, unregistered the test-produced Debug extension and registered Release; pluginkit confirmed only Release remained.
- Regression fixtures cover linked/individual inheritance, missing top-level and per-Space nodes, either mode alone, mode transitions, exact crash recovery, external edits, and failed reloads.
- Live standalone lock-screen playback and quit restoration on the rebuilt app remain unverified; no app restart, desktop control, or wallpaper change was performed.

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
