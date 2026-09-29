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

## 2026-09-29 — Resume the retained lock-screen renderer on wake

- Extension log identified the poster-only lifecycle: unlock destroyed the renderer; one wake took about three seconds from active host update to first-frame readiness.
- Throwaway offscreen Swift smoke compiled the production WallpaperSurface against the real renderer and bundled silent video, with isolated storage/host adapters and an unhosted CAContext. Before: failed because unlock replaced the Metal layer with a poster. After: passed with the same Metal layer, changing video pixels and exactly one readiness frame across both display-first and host-first wake sequences; user pause remained effective.
- python3 scripts/test.py --only WallpaperPresentationAuthorityTests: 13 passed, covering suspension precedence, both wake orders and user pause.
- Two initial full gates failed on obsolete whole-dictionary sidebar assertions that omitted the existing Pixiv page. Removed default/schema and forwarding assertions; retained sidebar interaction, layout and per-page persistence checks. No panel product code changed.
- python3 scripts/test.py --only ControlPanelLibraryTests/testFilterSidebarTogglesFromTheToolbarPerPageAndInspectorFollowsWindowWidth: 1 passed.
- Final python3 scripts/test.py: 215 Python passed; 735 native passed, 0 failed, 11 skipped of 746. Skips: nine opt-in native-media cases and two live Workshop network cases.
- Tradeoff: lock-screen scene/device memory remains resident while paused; memory and power impact not measured. Obsolete unload/reload policy and poster conversion helper removed.
- No Release build, app installation/restart, wallpaper change or real lock/sleep desktop run. System snapshot handoff and visible wake timing remain unverified; new surfaces still require initial loading.
- Removed the throwaway smoke harness, executable and cache with the repository cleanup helper; preserved pre-existing artifacts and built apps.

## 2026-09-29 — pixiv tab, sign-in and R-18 works

Written in a Linux container with no Xcode, then rebased onto main at 1.1.0 (command queue): the Foundation-only pixiv services ran under SwiftPM, the panel page under Chromium; nothing macOS-specific was built or run.

- Linux SwiftPM harness (Swift 6.1.2, `App/Services/Pixiv` and `Tests/Unit/Pixiv` with Darwin stand-ins) — `swift test`: 54 passed (service 25, store 15, packager 8, queue 6), three runs after the rebase; library clean under `-strict-concurrency=complete`
- `python3 -m unittest discover scripts/tests` — 198 ran, OK, 10 skipped; `node --check` on every `WebUI` module
- Chromium/Playwright with a mocked native bridge (not WKWebView) — pixiv tab browse, filters, paging, inspector, downloads and the account group (signed out, signing in, signed in, log out, R-18 hidden), Mature box and R-18 rankings; en and zh-Hans at 760–1240 px, no overflow, no page errors
- Anonymous pixiv answers (ranking, search, pages, status) decode; `daily_r18` answers 403 anonymously. Signed-in answers and the real sign-in page were not checked
- XcodeGen 2.46.0 (Linux build) regenerated `WallpaperMachine.xcodeproj` from main's: pixiv files added, nothing else changed
- Not run: `python3 scripts/test.py` (needs macOS and Xcode), so `WebPanelPixivTests`, `ControlPanelPixivTests` and every native suite; `PixivSignInWindow`, keychain and WKWebView behaviour; no Release build
- `python3 scripts/check_renderer.py` — not applicable: no renderer or bridge change

## 2026-09-28 — Busy state: queue user commands instead of erroring

- python3 scripts/test.py: 664 passed, 0 failed, 11 skipped (Python script tests all OK).
- Targeted: UserCommandQueueTests, WallpaperActivationRecoveryTests, ControlPanelLibraryTests, ControlPanelShellTests passed.
- Throwaway offscreen panel smoke (deleted): queued 'target' waited behind a held command with no error; tile ring showed Applying/queued, pointer-events none, error banner hidden.
- Not checked: live desktop switching and visual look of the rings (no desktop run authorized); Release app not rebuilt.

## 2026-09-29 — Review fixes on native Metal target pruning and the lock-screen poster

- Follow-up to #9 (squash-merged as 5567aab without these fixes); commits rebuilt on that main, tree identical to the gated one below.
- New ACopySkippedByTheOptimisationGetsItsImageWhenItIsTurnedOff failed when ReferencedRenderTargets skipped Copy target keys (the other 5 optimisation/target tests still passed) and passes as committed; full metal_scene_draw_smoke: 39 passed, 1 skipped (no local project).
- WE_TEST_METAL_FRAMES: WE_TEST_FRAMES=1 now skips instead of failing without projects; "abc" fails with a range message; one local scene drew 30 frames with WE_TEST_FRAMES=4 set and printed render-target bytes (240254976) beside device bytes (325681152).
- python3 scripts/test.py --only LockScreenPosterTests: 1 passed (extension target built with kCVPixelFormatType_32BGRA).
- python3 scripts/test.py: 198 Python passed; 672 native passed, 0 failed, 11 skipped of 683.
- python3 scripts/check_renderer.py: 24 binaries passed, 10 generated pixel comparisons equal, 8 projects x2 reloads 0 failures; three asset-dependent tests skipped.
- Not changed: the poster still wraps the IOSurface in a CGImage (IOSurface as layer contents needs a colour-tag decision and a real lock/unlock check); the 8 MiB Vulkan block size is unmeasured for allocation count and load or frame time (generated fixtures are too small).
- Not run: desktop lock/unlock, Release build.

## 2026-09-28 — Native Metal allocates only graph-referenced targets

- New UnreferencedTargetsStayUnallocatedAcrossOptimizationChanges regression failed on old allocation logic and passed after filtering both compile and live-toggle paths; output stays identical through on/off/on.
- scripts/check_renderer.py passed: 23 binaries, ten generated pixel comparisons, eight projects x2 reloads; three asset-dependent cases skipped.
- Full scripts/test.py with CPython 3.12.14 passed once for this change: 190 Python; 664 native passed, 11 skipped.
- Same local native scene at 120/240/360/540/720/900 frames: all six checkpoint images byte-identical, covering a full 15-second crossfade. Metal-reported allocation savings median 79.5 MiB, range 56.5–102.5 MiB as drawable residency varied.
- Fresh-launch live native comparison, closed panels and last three ten-second samples: main median 400.7 to 380.3 MiB; total app coalition plus separate extension 451.4 to 430.9 MiB. The smaller physical-footprint change is reported separately from Metal allocation counts.
- Renderer/bindings and Release builds passed. Signed app installed in /Applications with backup and relaunched using Codex computer use; logs confirm native Metal and first-frame readiness, same wallpaper playing, only installed extension registered.
- Prefer Native Metal was selected through the UI for this experiment and remains selected. The before/after native builds used identical config; resolution and FPS settings were preserved. The app default renderer preference is unchanged in code.
- Native-only resource pruning retains final output, every pass output/copy source/texture input, hidden draws and elided copies; declaration-only shadow/mip/bloom buffers stay unallocated, including after live optimization toggles.
- Real user-operated lock/unlock remains unverified. Private assets, frames and traces stay outside Git; no universal memory ceiling or CPU saving claimed.

## 2026-09-28 — Trim idle reservations and share lock-screen poster storage

- scripts/check_renderer.py passed: 23 binaries, ten generated pixel comparisons, eight projects x2 reloads; three asset-dependent skips.
- Full scripts/test.py with CPython 3.12.14 passed once: 190 Python; 664 native passed, 11 skipped. LockScreenPosterTests passed independently and verifies retained pixels plus eventual release.
- Apple VMA preference 32 to 8 MiB: same-scene reservation 231.4 to 203.4 MiB, active allocations unchanged at 198.1 MiB, blocks 8 to 10; three comparison frames identical.
- Previous texture policy checked across a complete 15-second crossfade: all 17 frames byte-identical against full-source rendering; visible changed-layer frames differ from startup by over 13 million bytes. The earlier two-second test missed these layers.
- Poster now retains its read-locked snapshot through a no-copy Data provider. The explicit 3024x1964 BGRA copy (22.7 MiB) is removed; extension footprint remained around 38 MiB, so an equal footprint saving is not claimed.
- Renderer/bindings and Release builds passed. Signed bundle installed in /Applications with backup and restarted using Codex computer use; saved configuration identical.
- Live logs show desktop first-frame readiness and extension poster readiness/unload at 3024x1964. Only installed extension registered; intermediate registration-contaminated samples excluded.
- Live app-plus-extension totals after settling varied around 402–509 MiB, later 504.9 MiB. WebKit lifetimes and GPU accounting prevent attributing another large whole-app reduction; component reservation is the controlled evidence.
- Real user-operated lock/unlock still pending. A closed-window lifetime hypothesis was tested but not reproduced; its experimental code was removed. No new quality or buffering tradeoff introduced.

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
