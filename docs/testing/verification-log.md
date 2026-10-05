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

## 2026-10-05 — Discover Collections fill screened pages to 30

- Cause: under the default Everyone-only rating, WorkshopService.collections drops collections whose sampled wallpapers are Questionable/Mature; live Steam page 1 (trend, 365 days) kept 9 of 30.
- Fix: WorkshopStore.filledPage fills each panel page from consecutive screened Steam pages (cursor per page, cap 10, next page fetched alongside); page/result counts are estimates; jumps start at an estimated Steam page.
- python3 scripts/test.py --only WorkshopSourceTests: 18 passed (new testScreenedCollectionsFillEachPageFromTheSteamPagesAfterIt).
- python3 scripts/test.py --only WorkshopStoreTests: 10 passed.
- python3 scripts/test.py: 1171 passed, 0 failed, 14 skipped.
- Not checked: the live panel against Steam (no desktop run); Release build follows.

## 2026-10-05 — Discover source tabs (Your subscriptions findable)

- Change: Discover's source <select> replaced by a tab row (Wallpapers / Collections / Your subscriptions) heading the toolbar; signed-in subscriptions summary leads with a primary Download-missing button, count and Sign out; empty subscriptions offer Browse Workshop.
- python3 scripts/test.py --only ControlPanelDiscoverTests --only WebPanelWorkshopSourceTests: 10 passed (new testDiscoverListsAreTabsAndSubscriptionsLeadWithTheirDownload, incl. one-row tabs at the 760px minimum with filters open).
- python3 scripts/test.py: 1170 passed, 0 failed, 14 skipped; Python localization catalog tests OK.
- impeccable detect on WebUI/panel.css, panel.js: no findings.
- Gap: no visual/desktop check (no screenshot authorization); layout verified only through offscreen WKWebView DOM geometry.

## 2026-10-05 — Local XHR startup compatibility for web wallpapers (landed on main)

Commit 41e88a2 (2026-10-03) existed only on a local main worktree; applied onto current main on 2026-10-05. Its original 2026-10-03 entry is carried over below, and the gate was re-run on the new base.

- 2026-10-03: private offscreen WKWebView probe with the original host script reproduced a local settings-loader JSON parse failure and retained splash. With the fix, the same read-only assets initialized a 1920×1080 canvas, removed the splash and reported no script errors across six samples. Audio/capture disabled, nonpersistent storage, no window or screenshot; desktop animation remains unverified.
- 2026-10-03: `python3 scripts/test.py --only WebWallpaperLocalRequestTests` — exit 0; 4 passed, covering synchronous startup, empty responses, async callbacks, JSON/binary bodies, missing files, abort, reuse and non-file metadata.
- 2026-10-03: full `python3 scripts/test.py` — exit 0 on retry after one picker-cancellation timeout that passed alone without code changes; 229 Python and 1075 native tests passed, 12 opt-in skips.
- 2026-10-05, on current main: `python3 scripts/test.py` — exit 0; 1169 passed, 0 failed, 14 skipped (media/network opt-ins). Conflicts were only the verification logs and the generated project; the project was regenerated with xcodegen.
- No renderer source changes; renderer gate not required. No desktop control, wallpaper changes, live audio, installation or app restart.

## 2026-10-05 — Native video keeps playing when its audio output cannot start (issue 31)

Workshop 3582362359 (H.264 Main@5.2, 2880x2160, 60 fps, AAC) was handed to Compatibility with AVErrorUnknown. Reproduced in a scratch AVPlayerLooper probe: while this Mac's audio output could not start, any clip with audio, including a generated control clip and a muted player, failed with -11800 over OSStatus -66681 (kAudioQueueErr_CannotStart); a missing output device fails with -11800 over -12746. The same clip with only its video track played at 60 fps in both cases.

- `WALLPAPER_MACHINE_MEDIA_TESTS=1 python3 scripts/test.py --only NativeVideoPlaybackFailureTests --only NativeVideoWallpaperHostTests --only NativeVideoPlayerMediaTests --only NativeVideoAdmissionTests --only SyntheticVideoFixtureTests` — 62 passed, 0 skipped
- With the fallback disabled, `NativeVideoPlayerMediaTests/testAClipWhoseAudioCannotStartKeepsPlayingItsPicture` fails (the clip is handed off); restored afterwards
- `python3 scripts/test.py` — 1165 passed, 0 failed, 14 skipped (media/network opt-ins)
- Compatibility path with the Workshop clip (temporary `unchanged_present_test` case, reverted): ~380–400 MB footprint, 400–580 MB Metal, flat over 40 s at 2560x1440; no VRAM growth reproduced
- Gap: the Compatibility black desktop in the report was not reproduced; one Compatibility run during the audio fault took 229 s instead of ~4 s with the stall unlocated, and a rerun after audio recovered did not repeat it
- Not run: `check_renderer.py` (no renderer change), desktop playback of the Workshop item

## 2026-10-05 — Issue #30: frozen panel, false first-frame timeout, poster refusal loop

Three fixes from one multi-display report: panel.js send() no longer strands a pending key when its busy render throws (the next tab click spun an endless microtask loop); the bridge facade waits for a first frame only where the engine opens or replaces a scene, judged against its live display snapshot instead of its own stale cache; the poster ledger leaves a desktop that keeps refusing posters alone until a Space change or wake.

- `python3 scripts/test.py --only ControlPanelShellTests/testTabsStayUsableAfterARenderThrowsWhileSending` against the unfixed panel.js — failed (page hung, execution time allowance); passes with the fix
- `python3 scripts/test.py --only DesktopWallpaperTests/testDesktopThatKeepsRefusingPostersWaitsForTheNextSpaceChange` against the unfixed ledger — failed (refusals rose 4 → 9; XCTest then stalled recording the assertion until the allowance); passes with the fix
- `cargo test -p wallpaper-bridge --lib first_frame_tests` — 3 passed
- `python3 scripts/check_renderer.py` — exit 0; skipped: 4 local-corpus tests (TextObjectRuntime ×2, AppleVideoFrame.LocalVideoImportsVisiblePixels, MetalSceneDraw.LocalProjects…)
- `python3 scripts/check_rust.py` — exit 0; core 222, bridge 381 passed; shader skipped 3 corpus cases
- `python3 scripts/test.py` — exit 0; 1173 tests: 1161 passed, 12 skipped
- Not verified: the reporter's 4-display Mac, real WallpaperAgent refusals, and that their freeze was this exact page loop (no panel console log was available); the SIGABRT in SharedVideoSourceHandle::prime and the raw BridgeError banner text are not addressed

## 2026-10-04 — Workshop preset media, background-copy masks and script property order (#28)

Issue #28: preset 3610485014 (base 2983846453, a day/night switch template) drew a black background and an unclipped switch at the canvas centre. Diagnostics showed native Metal falling back on files/*.mp4. Both items were fetched with the user-approved saved Steam session into a disposable scratch directory and assembled the way the importer does; nothing from them is committed.

- Before: `metal_scene_draw_smoke` (local project) fell back on the missing `files/*.mp4`, then on `link tex 89 not found`; layer 32's script moved the switch by 0 instead of the preset's (+1346, +830).
- After: native Metal accepts the scene (120 frames, no fallback), and `offscreen_scene_probe` (Vulkan) shows the same picture: video background, switch top right, clipped to its pill. This matches the reporter's Windows screenshot by eye; no pixel reference.
- New regressions, each confirmed failing without its fix: `SceneSourceMount.APresetFileBesideThePackageLoadsAndThePackageStillWins`, `LayerTextureReference.ABareComposeLayerAnotherSamplesIsDrawnOnlyIntoItsComposite`, `ScriptRuntimeCompat.ModuleCodeSeesDeclaredDefaultsAndInitSeesTheBoundValue`.
- `python3 scripts/check_renderer.py --project <assembled preset>`: exit 0. All generated cases are pooled/isolated equal with 0 diagnostics; the preset is pooled/isolated equal with 4 known diagnostics (`.mp4.tex` probes before the loose fallback, and the clock script's `createLayer({text})` drop shadow, which is unsupported and hidden). Skipped: corpus-dependent text_object_runtime, playback_gpu local video and metal local-project tests (env unset).
- `python3 scripts/test.py`: exit 0; 1157 passed, 12 skipped of 1169.
- `python3 scripts/build.py --configuration Release`: the first run failed configuring wallpaper-core, because a compiler-path change reset its stale CMake cache without the build script's `-D` flags; the unchanged retry built the app. Bindings were regenerated unchanged.
- Not verified: desktop or app run, clicking the day/night switch, audio bars. Text-layer `padding` given as an "x y" string still parses to 0 (pre-existing; no visible effect here).

## 2026-10-04 — v1.2.4 hosted-runner timer precision gate

- Cause: v1.2.4 Release runs 37185728032, 37188243177 and 37190006244 failed 'Renderer regressions without a desktop' (new in v1.2.4) on wall-clock cadence tests: 11 ticks of a 10 ms cadence in 600 ms, ~10 fps at a 60 fps ceiling; the background-priority reset (265339e) did not change it.
- Fix: check_renderer.py --allow-imprecise-timers compiles a probe (median of 31 condition-variable 10 ms waits); only its exit 77 (median > 20 ms) filters the nine REALTIME_TESTS by --gtest_filter and records each as a warned skip; build.yml passes the flag.
- Probe locally: 11.0 ms median (exit 0); under taskpolicy -b: 47.95 ms (exit 77), matching the CI signature.
- Filtered timer_tests (29), audio_tests (51) and unchanged_present_test (1) all passed on the local binaries; no filtered name ran.
- python3 scripts/check_renderer.py --skip-build --allow-missing-gpu --allow-imprecise-timers: exit 0, every cadence test executed, 12 generated scenes matched, reload 8x2 passed.
- A first full-build run failed FrameTimerTest.AnIdleBurstOfWakeOnceProducesOneCallback once under load average ~6; 0/40 on repeat, unrelated to this change, passed on all three CI runs.
- python3 scripts/test.py: Python suites passed (test_check_renderer 26 tests); native 1156 passed, 0 failed, 12 skipped.
- Gap: the hosted-runner skip path is proven only through mocked gate tests until the v1.2.4 Release run; no desktop, app launch or Release rebuild.

## 2026-10-04 — v1.2.4 background runner regression

- Reproduced the CI timer failure with taskpolicy -b; application scheduling alone did not clear inherited Darwin background policy.
- Child-only process and main-thread priority reset preserves real-time assertions; 20 renderer harness Python tests passed, including background inheritance and exit-status propagation.
- /usr/sbin/taskpolicy -b python3 scripts/check_renderer.py --skip-build: passed all required binaries, all 12 generated scene pixel comparisons and expected pixels with zero diagnostics, and eight reload projects twice.
- python3 scripts/test.py: Python checks passed; native suite 1156 passed, 0 failed, 12 optional media/network tests skipped.
- User commit 9a63ed3 and its bilingual release note remain included. Optional local wallpaper/video corpus tests were skipped; no desktop launch, install, audio hardware, or visual smoke test was performed.

## 2026-10-04 — Normalize complete puppet poses across animation layers

- Original synthetic regressions: both NonAdditive tests fail against the original WPPuppet.cpp and pass with the correction.
- CMake mdl_schema_tests and scene_schema_tests: exit 0; 57 model and 109 scene tests passed.
- python3 scripts/test.py: exit 0; Python checks passed, native gate 1156 passed, 0 failed, 12 opt-in media/network skips.
- python3 scripts/check_renderer.py --project <local-project>: exit 0; all 30 registered binaries succeeded; 12 generated scenes and one local scene had pooled/isolated pixel equality and zero diagnostics; local reload x2 passed.
- Renderer gate skipped two optional private text scenes, a private video import and its unconfigured local Metal case; the affected local scene was separately rendered successfully by metal_scene_draw_smoke.
- Private offline renders of Into The Abyss inspected at scene time 15 seconds on Compatibility and native Metal: hair and arm reassembled. Compatibility before/after both used 1024 passes across 16 samples and 276121600 allocated GPU bytes.
- python3 scripts/build.py --configuration Release: exit 0; rebuilt renderer and Release app. No installation or launch.
- git diff --check passed. Desktop presentation, live smoothness and energy use unverified; no desktop control, screen capture or audio hardware used.

## 2026-10-04 — PR 25 declaration-scoped arrays and camera FOV

- Resolve stage-interface macro bounds at each declaration, including intervening and function-body directives; freeze literal bounds before hoisting/input-copy emission. Shader pipeline revision 10 -> 11 invalidates previously cached stale-sized programs.
- Omitted/nonpositive camera FOV inherits immutable authored scene settings; named camera creation, runtime shots and non-runtime playback share the resolved value. Positive object overrides remain authoritative.
- `cargo test -p shader -- --nocapture` with the project Cargo environment — exit 0; 515 reported passed, including three unavailable asset-dependent early-return skips. SPIR-V/MSL per-declaration and undefined-macro regressions passed.
- Camera-targeted scene-schema run — 20 passed. Rebuilt full scene_schema_tests with the current shader library — 109 passed, including named/default cameras, scene/shot overrides and visibility fallback in both playback paths.
- `python3 scripts/build.py --renderer-only` — passed; generated bridge bindings unchanged. No Release app build.
- `python3 scripts/check_renderer.py` — every recorded binary exited zero; all 12 synthetic pooled/isolated pairs matched with zero diagnostics; eight projects completed two reload cycles.
- `python3 scripts/test.py` — all Python suites passed; 1,156 native passed, zero failed, 12 skipped.
- Corpus gaps: three shader cases, two renderer text scenes, the optional local video import case and environment-selected Metal projects skipped; these are not verified asset coverage.
- `git diff --check`, provenance JSON and generated-binding consistency passed. No desktop visual/live keyboard validation, authored-reference parity claim or app launch.
