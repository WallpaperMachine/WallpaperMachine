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

## 2026-09-29 — Retain wallpaper presentation across wake topology changes

- Hidden-window Rust smoke: before the fix, three origin/primary/refresh updates performed 3 drawable-size writes and 3 forced AppKit redraws; afterward both counts were 0 with the same layer, and a real resize still produced a 256x144 window/drawable at scale 1. Window ordering was suppressed; no wallpaper or visible desktop window was changed. Temporary smoke removed.
- LockScreenWallpaperServiceTests/testWakeDisplayLookupGapPreservesCommittedWallpapersAndRecovers failed before the Swift fix and passed afterward; partial/all-display lookup gaps preserve manifest, native selection, provider ownership and the status monitor, then settled disconnect and last-wallpaper removal still reconcile.
- python3 scripts/test.py --only LockScreenWallpaperServiceTests: exit 0, 14 passed, 0 failed, 0 skipped.
- python3 scripts/test.py: exit 0; all 17 Python modules passed; native 746 passed, 0 failed, 11 skipped (9 opt-in media and 2 live Steam cases).
- The initial targeted launch in Background exited 250 with IDELaunchServicesLauncher childPID > 0; the failing-before, passing-after and full native runs used a temporary same-user Aqua launch job. Jobs and temporary runners removed.
- cargo test --release -p wallpaper-core --lib with the build.py cargo environment: exit 0; runner reported 222 passed. Opt-in desktop/private-asset cases were not enabled; this is not physical wake proof.
- python3 scripts/check_renderer.py: exit 0; generated ten-scene pooled/isolated pixel comparisons matched, no diagnostics, and 8 projects x2 reload cycles passed. No user wallpaper corpus was requested.
- Real external-primary lid/sleep/wake visual timing remains unverified. No Release app build, launch, install, desktop automation or screen capture; the running app still has its previous behavior.

## 2026-09-29 — Bilingual post-update What's New

- Implemented native post-update window, persisted opt-out and version-range history; all 18 historical releases now contain English and Simplified Chinese.
- Isolated swiftc smoke: actual native content laid out offscreen at 560×400; 1.0.2 → 1.1.0 includes both releases and their complete translations; checkbox persistence and Close callback passed. No windows opened.
- python3 scripts/test.py --only WhatsNewTests: initial Background-session launcher failed with exit 250 before tests; same command through a temporary same-user Aqua launch job passed 7/7, exit 0.
- python3 scripts/test.py through the Aqua job: 17 Python suites passed, including 51 release-note tests; native result 745 passed, 1 failed, 11 skipped of 757, exit 65.
- Shared-workspace blocker: LockScreenWallpaperServiceTests.testWakeDisplayLookupGapPreservesCommittedWallpapersAndRecovers failed while preserving enabled state and committed topology. This concurrently added test is absent from HEAD; its test and service edits were not changed by this task. Commit withheld because the full gate did not pass.
- python3 scripts/release_notes.py --tag v1.1.0 --release-body --output <temporary-file>: exit 0; actual output matches the recorded current notes exactly, and all bundled historical sections passed bilingual publication validation.
- History comparison: all 18 version/date headings, English notes and compare links preserved; translated bullet counts match. cmp confirmed Debug-bundled CHANGELOG.md is byte-identical to the source.
- Skipped: 9 opt-in native-media and 2 live Workshop tests. No live release-note model call, desktop visual check, Release build, install or app restart performed. Temporary Aqua job removed.

## 2026-09-29 — Multi-display lock-screen fix gate and Release delivery

- Resolved the previous native-launch blocker without changing the test command or product code: launchctl managername reported Background for the detached tool session; a temporary same-user launch job ran the existing gate in Aqua. Serial and environment-only changes had not resolved childPID > 0.
- python3 scripts/test.py --only LockScreenWallpaperServiceTests in Aqua: 13 passed, 0 failed, 0 skipped, including the synthetic display topology regression.
- python3 scripts/test.py in Aqua: 215 Python passed; 738 native passed, 0 failed, 11 skipped of 749. Skips: nine opt-in native-media cases and two live Workshop network cases.
- python3 scripts/build.py --swift-only --configuration Release: passed; built build/Build/Products/Release/WallpaperMachine.app with the atomic topology publication and same-display context-preserving resize fixes.
- codesign --verify --deep --strict passed; diff -qr WebUI against the delivered Contents/Resources/WebUI returned no differences.
- Temporary gate jobs were booted out; task-owned helper files and four suspended orphan test hosts from the failed launches were removed. No installed/running user app was replaced, launched or restarted.
- Real external-primary/internal-secondary lock and wake visual timing remains for user verification. No desktop control, screen capture or wallpaper changes were performed.

## 2026-09-29 — Preserve lock-screen surfaces through multi-display topology changes

- Existing app/extension logs correlated display refresh bursts with manifests changing 2 -> 0 -> 1 -> 2; one empty manifest cleared every surface and its frame backing. Logs also include old registered extension binaries, so they do not establish a clean live visual result.
- Standalone Swift publication smoke compiled the production service/selection with isolated bridge and user-asset adapters. Before: transitions to [1], [1,2] and [2] each published [] first (exit 1). After: each published only the complete destination set; explicit disable still cleared scenes (exit 0). No real wallpaper-store writes or WallpaperAgent signals.
- Standalone offscreen GPU smoke compiled the production WallpaperController and WallpaperSurface against the real renderer and bundled video. Two synthetic display IDs kept distinct unhosted contexts; a secondary 1x-to-2x resize retained its context/backing until the 768x496 replacement frame, preserved the primary context and rejected invalid geometry without clearing the good frame.
- New permanent topology regression executed through a temporary standalone XCTest bundle: 1 passed. Production service/selection were compiled into an isolated module; bridge and unused managed-user-asset dependencies were fixture adapters. This is not the full app-hosted gate.
- python3 scripts/test.py: 215 Python passed; native app, extension and tests compiled, then Xcode aborted before executing native tests with IDELaunchServicesLauncher childPID > 0 (exit 250). Targeted parallel, serial, PTY and cleaned-launch-environment attempts hit the same launch failure. Debug bundle codesign --verify --deep --strict passed.
- Native gate blocked, not passed: no commit or Release build. No app installation/restart, display reconfiguration, real lock/wake run or screen capture. Private XPC/compositor handoff timing remains visually unverified.
- Removed task-owned smoke programs, XCTest bundle/module and shader cache through the cleanup helper; retained pre-existing artifacts and delivered apps.

## 2026-09-29 — Commit wallpaper pixels before lock-screen context handoff

- Readback readiness previously acknowledged only an IOSurface in Swift memory, leaving the remote layer tree without backing pixels until a drawable became available. Now commits an IOSurface-backed image under the nonopaque Metal layer with implicit actions disabled, before readiness replies; does not wait for scanout or unload the paused renderer.
- Standalone offscreen Core Animation smoke: old unbacked composition exposed white host pixels [255,255,255,255]; corrected composition returned wallpaper pixels [19,47,83,255] with the same Metal layer and no drawable. No window or screen capture.
- python3 scripts/test.py --only LockScreenFrameBackingTests: 2 passed after correcting a CoreFoundation cast compile error. Covers no-drawable pixel composition and release/retention across snapshot replacement.
- python3 scripts/test.py: 215 Python passed; 737 native passed, 0 failed, 11 skipped of 748. Opt-in media/network cases remain skipped.
- Scene replacement retains backing until new pixels arrive; explicit clear releases it. The image shares the immutable snapshot storage without another bitmap copy; compositor memory and power impact not measured.
- Recurring host reacquisition was observed in the existing extension log, but its cause is unproven. A third-party snapshot-encoding hypothesis was not verified on this OS; no private-method swizzle, snapshot-freshness change or retry logic added.
- Real lock/wake visual timing and private XPC transport remain unverified. No desktop manipulation, Release rebuild, app installation or restart. Removed this task's standalone smoke files only; existing artifacts retained.

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
