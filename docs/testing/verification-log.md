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

## 2026-09-28 — Review follow-ups: reconnected displays, held buttons, owed frames, late-created Spaces

Pre-push review of perf/wallpaper-power (four reviewers, each finding checked by a skeptic): 6 confirmed, 8 rejected. Each fix has a test that fails without it.

- Reconnected display: a display that disconnects while suspended and returns visible is resumed; one that returns still hidden stays suspended with no resume/suspend pair (WallpaperPresentationPolicyTests, 2 cases).
- Pointer: button levels are adopted without edges after the monitors return (wallpaper-core 222 passed).
- Frame clock: 18 ms draws at 60 fps deliver ≥42/s (35 without the owed-frame path, measured with a spinning draw because sleep_for(18 ms) slept ~22 ms here); requests after a long content-paced wait stay within the ceiling; timer_tests 32 passed, three consecutive runs.
- Lock screen: turning off restores a Space created after the last check (test failed without the fix: node left on the extension).
- `python3 scripts/test.py` — 671 passed, 0 failed, 11 skipped. `python3 scripts/check_renderer.py` — 24 binaries exit 0, 10 generated cases pixel-equal, reload cycles 0; 3 asset-dependent gtest cases skipped. Release build signed.
- Not re-measured on hardware after these follow-ups: power figures in the earlier entry stand for the code measured then.

## 2026-09-28 — Lock screen: a Space created while active no longer turns the feature off

M3 Max, macOS 27.2; AllSpacesAndDisplays held only another app's Idle choice. After activation macOS had copied the extension's selection into SystemDefault and some Space Defaults, so a new Space started from those copies and restorationOriginal found no native fallback in the live store. Space creation and toggling Animate Lock Screen were done by the user on request.

- Reproduced on the unfixed build: adding a desktop in Mission Control logged the missing-restoration error at the next check, deactivated the feature and left the new Space's Default and display nodes pointing at the extension.
- Fixed build: a second new desktop was journaled (70 → 72 entries, originals = system image desktop and the other app's idle, from SystemDefault's journaled original), no error; turning the feature off left no store node pointing at the extension, both new Spaces restored, journal removed.
- `python3 scripts/test.py --only LockScreenWallpaperTests --only LockScreenWallpaperServiceTests` — 31 passed; the new test failed with the same error before the fix.
- `python3 scripts/test.py` — 669 passed, 0 failed, 11 skipped.

## 2026-09-28 — Power: covered-desktop pause, 60 fps default, frame-clock slack, WindowServer attribution

M3 Max, macOS 27.2, built-in XDR at 120 Hz in a 4112x2658 scaled mode, AC; coalition energy without root over 40–45 s windows run in alternation, other apps hidden (NSRunningApplication.hide) for the exposed-desktop runs; desktop A/B, probe window and xctrace authorised by the user. Baseline B0 = local Release build of 78ebc9c; candidate B1 = this change.

- Attribution, Lucy (3521337568) exposed: B0 at ~89 fps app 5.0–5.2 W, WindowServer 0.51 W, system 31–32 W; B1 default (60 fps delivered) app 3.0–3.3 W, WindowServer 0.22–0.33 W, system 22–24 W. Probe WindowServer 31–39 mW idle, 197–213 at 30 fps, 268–364 at 60, 495–571 at 120.
- Covered-desktop pause (smoke_i1, B1): exposed keeps rendering (app GPU 2.3–3.3 W); a zoomed-size window pauses display 1 after the settle (app GPU 0, WindowServer 365 → 23 mW); removing it resumes at once; a window leaving desktop visible does not pause; desktop clicks hit Finder's desktop window. User-driven Space switch, full-screen app and Mission Control: pause/resume pairs as expected, no stuck state.
- Measured, not adopted: present pacing (plain / afterMinimumDuration / CAMetalDisplayLink equal at 60 fps), drawable at panel or half size (no difference), layer colour space (probe −33 % WindowServer, Lucy 12–75 mW inside spread). Unverified: ProMotion panel dropping below 120 Hz (traces disagreed); sudo powermetrics not run.
- `python3 scripts/test.py` — 668 passed, 0 failed, 11 skipped; Python script tests all OK (test_power_benchmark 28).
- `cargo test --release -p wallpaper-core --lib` 221 passed; `-p wallpaper-bridge --lib` 360 passed (first run hit the documented CMake configure retry). timer_tests 30 passed; the new cadence test fails without the fix (50 ticks).
- `python3 scripts/check_renderer.py` — 24 binaries exit 0, 10 generated cases pixel-equal, reload cycles 0; 3 asset-dependent gtest cases skipped (metal_scene_draw_smoke 1, text_object_runtime_test 2).
- Pointer monitors installed only while a scene reads the pointer: with the final build, Lucy (camera parallax) followed the mouse with the panel frontmost, after switching to another app and after a covered pause and resume (checked by the user). Untested for the covered-desktop pause: multiple displays, Stage Manager, tiled windows with gaps.

## 2026-09-28 — Display-sized packaged texture residency

- scripts/test.py with CPython 3.12.14: 190 Python passed; 663 native passed, 11 skipped. Full gate run once for this feature.
- scripts/check_renderer.py passed: 23 binaries, ten generated pixel comparisons, eight projects x2 reloads. Three asset-dependent cases skipped; the local Metal scene was tested separately.
- tex_schema_tests: 22 passed, including surface budget selection/reset, metadata preservation, pre-decode skipping, payload truncation and sprite/video exclusions.
- Current local scene: GPU allocated 457.1 to 198.1 MiB, reserved 490.4 to 231.4 MiB. Matched headless process peak 1175.4 to 622.9 MiB.
- Compatibility: five frames spanning two seconds with particle seed 42 and synthetic silent audio were byte-identical before/after; the frames differed over time.
- Metal: fixed local-project random-seed handling; full-source and budgeted seeded 120-frame runs ended with byte-identical images. Temporary baseline budget bypass was restored before final review.
- Live closed-panel samples, 3 per build 10 seconds apart: main median 735.5 to 458.9 MiB; whole app coalition plus separate extension median 786.3 to 509.4 MiB (after range 413.9–509.4). GPU accounting and settling samples fluctuate; no universal ceiling or CPU saving claimed.
- Renderer/bindings and Release builds passed. Signed app installed into /Applications with backup, launched using Codex computer use, same wallpaper playing and first frame ready. Saved configuration identical; only installed extension registered.
- Policy may reduce source detail under zoom and only limits available authored mip chains. Actual lock/unlock and the local-import close exception remain unexercised; private scene assets/images stay in artifacts.

## 2026-09-28 — Release the closed control panel to reduce memory

- Panel lifecycle follow-up: CPython 3.12.14 scripts/test.py --only ControlPanelWindowSizingTests --only ControlPanelShellTests --only ControlPanelSyncTests passed 30/30. Earlier full gate is recorded separately; not repeated.
- scripts/build.py --swift-only --configuration Release passed; installed signed result into /Applications/WallpaperMachine.app with the previous bundle backed up.
- Codex computer use confirmed original scene playback, close/reopen, Settings navigation and restoration of the last native section. No quality, audio, power or renderer settings changed.
- Old installed build retained 121.6 MiB across WebKit GPU/WebContent/Networking after closing. Updated build released WebContent/Networking immediately and GPU after its idle timeout.
- Same updated main PID 88547: total app coalition plus separate installed extension 904.6 MiB with panel open, 790.0 MiB after close and helper exit; main 734.8 to 734.7 MiB. This isolates panel residency, not a build-to-build benchmark.
- Fresh startup remained above 1 GiB before freed decode allocations were reclaimed; closing the panel does not solve the remaining scene texture/renderer memory.
- Existing native Metal local-scene harness drew 120 frames at 3840x2160; no demonstrated memory win and no live backend switch. Raw-mip copy experiment did not apply to this scene’s embedded PNGs and was removed.
- Local imports retain the hidden page until the next close to avoid cancellation. This exception was reviewed but not exercised with a real file picker; real lock/unlock remains pending user operation.

## 2026-09-28 — Reduce active-scene reservations and release unlocked lock-screen renderer

- Memory follow-up to the active-wallpaper report, not an idle-panel result. User approved unloading the unlocked lock-screen renderer and cold reloading on the next lock; original texture resolution, render scale, frame-rate ceiling and playback settings remain unchanged.
- `scripts/test.py` with CPython 3.12.14 — exit 0; 190 Python passed, 663 native passed, 11 skipped. Final `python3 scripts/test.py --only WallpaperPresentationAuthorityTests` — 14 passed; covers retained-poster eligibility, paused/sleeping/host-suspended reload refusal, and failed-reload retry boundaries.
- `python3 scripts/check_renderer.py` — exit 0; 23 test binaries, ten generated pixel comparisons, eight synthetic projects reloaded twice. Three asset-dependent cases skipped. Allocator regression fails under the prior policy (about 160 MiB unused retained allocation) and passes with the 32 MiB Apple block policy.
- Current local scene, three-frame offscreen comparison: allocator reservation 632,029,696 → 514,261,760 bytes (−112.3 MiB); live allocation 479,332,096 bytes unchanged; all three output frames byte-identical. Probe now reports image extents/allocation requirements, retired-upload allocator totals and process footprint/peak separately.
- `scripts/build.py --renderer-only` and `scripts/build.py --swift-only --configuration Release` — passed. Installed into `/Applications/WallpaperMachine.app`, signature checked, backups retained. Desktop-control actions used Codex computer use.
- Live unlocked-session observation on the same selected scene: earlier vmmap main 820.4 MiB and extension 624.8 MiB; final main 745.9–749.9 MiB and extension 38.7 MiB. Final app coalition plus separately measured extension: 915.5–923.9 MiB over three samples ten seconds apart. No claim that the remaining roughly 0.9 GiB is a solved low-memory target.
- Extension log confirms first-frame readiness followed by renderer unload while retaining its poster. Actual lock/unlock reload verification is pending user participation. No texture downsampling was applied; two 7680×4320 input images each require about 173 MiB on this scene.
- Corrected test-bundle extension registration pollution: unregistered non-installed copies, renamed the two task-owned benchmark apps to non-launchable backup bundles, and verified the single registered/running extension is under `/Applications`. Config comparison confirmed playback, quality, power and monitor assignments unchanged.
- Heap-pressure and prefetch/upload-overlap experiments were removed: no reliable useful gain on this scene (heap call reported zero; peak probe change about 6 MiB). Their measurements are not credited to the final change. Private wallpaper pixels, app copies and traces stay out of Git.

## 2026-09-28 — Release before-after resource measurements with Codex computer use

- Built baseline and modified Release bundles with `python3 scripts/build.py --configuration Release`; both exit 0. Baseline restores the four changed production files from `31fb981`; modified code is `075e85e` (subsequent commits are docs). Current source and normal Release build restored; benchmark bundles use isolated homes and identical signing treatment.
- Used Codex built-in computer use for the final A/B UI sequence. Same 1054×659 panel, Chinese locale, same 30 displayed Discover titles, six page-scrolls down and six up, then Command-W. No active wallpaper or quality/default changes. Both sessions seeded with the same 120 thumbnail-cache files, verified byte-identical; live adjacent-page prefetch differed by one unused animated preview/still pair.
- Collected three approximately 22-second closed-panel windows per build, 21 samples each. Every sample verified no on-screen test panel, exactly one WallpaperMachine instance, and a stable resource-coalition process set. These are repeated windows within one app session per build, not independent launches. Interrupted foreground attempts excluded.
- App plus helper CPU: baseline median 0.64%, range 0.25–1.02%; modified median 0.60%, range 0.45–3.94%. Ranges overlap and the first modified window was higher: no demonstrated idle-CPU improvement. Mach-absolute rusage times converted with the local 125/3 timebase, checked against ps cumulative CPU time.
- Physical footprint: baseline median 248.6 MiB, range 248.6–248.7; modified median 186.0 MiB, range 185.7–199.9. Observed difference −62.6 MiB (25.2%) in this browsing/closed-panel comparison, not a general playback or system-RAM claim.
- Summed process RSS: baseline median 551.4 MiB, range 551.0–551.5; modified median 426.5 MiB, range 426.3–432.2. Observed difference −125.0 MiB (22.7%). RSS may double-count shared pages; physical footprint is reported separately.
- Both benchmark apps quit through Codex computer use and their exit was verified. App preferences restored to the pre-run snapshot; no wallpaper was applied during this comparison. Existing app-code gates remain applicable; only documentation changed afterward.
- Limits: foreground/active-playback CPU and RAM still unmeasured under controlled conditions; the public Workshop page and neighboring-page prefetch are not a frozen network fixture. No broad CPU-saving or all-wallpapers RAM-saving percentage is claimed.

## 2026-09-28 — Authorized Release live check for preview and snapshot optimizations

- Explicit follow-up authorization: live desktop run on source `075e85e`. `python3 scripts/build.py --swift-only --configuration Release` — exit 0; the Release app contains the modified panel asset (SHA-256 matched the source).
- Release app launched with an isolated `WALLPAPER_MACHINE_HOME`; initial user desktop image URLs and app preferences were saved locally. Apple M5 Pro, macOS 27.0, built-in 3024×1964 display at 120 Hz; default Compatibility video, native render scale.
- Live functional checks: real Discover results and animated-preview cache loaded; Settings/Installed navigation and hide/reopen remained responsive. Aurora Drift applied through the UI and the renderer logged first-frame readiness. Pause and resume controls changed state correctly; timer stop/start and occlusion suspension/resume appeared in the runtime log. No Release-process crash.
- CPU/RSS sampled for the Release resource coalition, including its WebKit services. Discarded active-playback comparison: foreground changed repeatedly, and a separate Debug instance began running with the same bundle ID. No matched pre-change baseline or reliable whole-app CPU/RAM saving is claimed.
- UI targeting switched to the exact Release PID after detecting the second instance. Scrolling was attempted but its viewport movement and animation pixels were not independently verified; source-release behavior remains covered by the passing headless regression.
- Restoration: requested graceful termination of the Release PID only; it exited and logged renderer teardown. Desktop image URLs match the pre-run records. Other Debug instance left running. Only the shared window-frame preference differed; it was not overwritten while another instance owned it.
- No screenshots, screen/audio capture, live Steam login, installation, lock-screen/sleep-wake tests, or quality/default changes. Previous passing headless gates remain applicable; this follow-up changed documentation only.

## 2026-09-28 — Reduce invisible preview retention and repeated storage scans

- `scripts/test.py` with installed CPython 3.12.14 — exit 0; 190 Python tests passed; 660 native passed, 11 skipped, 0 failed. Initial Python 3.9 attempt stopped in unchanged brand tests (`zip(strict=True)`); the interpreter requirement is now in the testing guide.
- `python3 scripts/test.py --only ControlPanelDiscoverTests` — exit 0; 6 passed. Extended regression covers hidden loading, offscreen source release, scrolling/visibility resume, Settings retirement, still fallback and one download per URL.
- New Discover regression against unmodified upstream `panel.js` — failed as expected because hidden animations retained sources; modified code passes in the full gate.
- `cargo test --release -p wallpaper-bridge --lib` with the build environment — exit 0; 360 passed. A burst of 1,001 size requests performs one walk; expiry and explicit invalidation remeasure. Actor test covers immediate cache growth and clearing.
- `python3 scripts/build.py --renderer-only` — exit 0; rebuilt the bridge and regenerated bindings; no interface changes.
- `python3 scripts/check_renderer.py` — exit 0; 23 test binaries, 10 generated scenes with matching pooled/isolated pixels and no diagnostics, and 8 synthetic projects reloaded twice. Three asset-dependent cases skipped (two text scenes and native local-project coverage).
- Synthetic Rust 2024 optimized probe using production directory-size/cache methods: 1,000 queries over 256 files of 1 KiB, five runs per variant. Median elapsed 239.714 ms before vs 0.449 ms cached; ranges 237.600–251.058 ms vs 0.418–0.523 ms. Workload timing only; tiny RSS differences and rounded CPU-time samples do not establish app memory/CPU savings.
- Reviewed frame scheduling, bounded video queues, shared-decoder ownership, native-video teardown, web-audio subscription loops and extension surface release; no additional renderer/quality/default changes were justified.
- Headless only: desktop CPU/RAM, visual behavior, live Steam and opt-in media tests unverified. No wallpaper changes, desktop capture, app launch/restart or Release app delivery build.

## 2026-09-28 — Reconcile keeps unchanged scenes; launch-at-login read once per burst

Follow-up to 4ee91e5: full reconciles (Apply, display edits, backend switch, repair) now hand the engine live descriptors (frame-rate ceiling and transient mute applied), and the launch-at-login status is read from SMAppService at most every two seconds.

- `cargo test --release -p wallpaper-bridge` (build env) — before the fix `a_reconcile_does_not_reload_a_scene_held_to_the_frame_rate_cap` and `::…_muted_for_other_audio` failed (handed fps 120 / unmuted vs running 60 / muted); after: 359 passed, 0 failed, including the four `a_display_refresh_does_not_reload_*` tests from 4ee91e5
- `python3 scripts/build.py --renderer-only` — exit 0; regenerated bindings identical
- `python3 scripts/test.py` — exit 0; Python modules all OK; native 671: 660 passed, 11 skipped (opt-in layers)
- `python3 scripts/check_renderer.py` — exit 0; 10 generated scenes pooled and isolated exit 0, pixels equal, 0 diagnostics; reload cycles (8 projects x2): 0
- Not verified: a Release build or the live desktop; no manual unlock/Apply run against a real display
