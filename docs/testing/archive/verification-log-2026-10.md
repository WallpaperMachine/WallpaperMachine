# Verification log archive — 2026-10 and earlier

Retired entries from [../verification-log.md](../verification-log.md), moved
here when that log was capped at its ten newest entries. No recorded result was
rewritten: each entry is reproduced verbatim, and the only edit is that
relative Markdown links gained one `../` for this file's extra directory
level.

These are historical results about the trees they were taken on. They are not
evidence about the current tree and must never be cited as such.

## 2026-10-03 — Parent-controlled parallax keeps child layers aligned

- Resolved outermost-parent parallax once at parse time; no wallpaper identifiers, asset edits, new render passes, texture allocation or per-frame hierarchy traversal.
- scene_schema_tests: 100 passed, including declaration-order/cycle/default-depth resolution and parsed multi-slot puppet displacement with unchanged local transforms.
- MetalSceneDraw.ParentedCardsStayJoinedWhileParallaxMovesAndReverses: passed for direct/effect cards and repeated/reversed cursor motion; removing only the inheritance call in a private build makes its pixel assertion fail.
- check_renderer.py with an isolated artifact root: 507 passed, 3 asset-dependent skips; 11 generated pixel cases and the selected local wallpaper match pooled/isolated allocation, no diagnostics; two reload cycles passed.
- The first additional private-scene comparison failed only in 769 live-clock pixels. Retry used WE_TEST_PROPERTIES to hide its clock in memory; no imported files or saved user settings changed.
- Matched eight-frame Vulkan probes with synthetic pointer input reproduce detached head/flowers without inheritance and aligned pieces with it; both execute 1095 passes, reuse 49 and allocate 114272640 VMA bytes. This is not a battery/performance benchmark.
- python3 scripts/test.py: 1071 passed, 0 failed, 12 skipped; all Python script modules passed. No desktop/UI, live network or media-device opt-ins.
- python3 scripts/build.py --configuration Release: passed; delivered build/Build/Products/Release/WallpaperMachine.app, not launched or installed.
- Shared workspace contained concurrent shader/camera/model/UI work. A transient unrelated ParseCameraPaths test declaration blocker cleared before verification; unrelated edits remain separate.
- Desktop presentation, real cursor interaction and animation smoothness remain unverified; all image inspection was surface-free offscreen output.

## 2026-10-03 — Restore perspective shots and skeletal model playback

- Implemented runtime perspective-shot selection, packaged eye/center/up/FOV camera paths, shared skeletal-model playback and model-specific opaque depth/cull defaults; no wallpaper-specific rules or asset edits.
- scene_schema_tests: 100 passed, including five new camera/model regressions; orthographic camera coverage remains green.
- python3 scripts/test.py: passed; 229 Python tests, 1,071 native tests passed, 12 native skips.
- python3 scripts/check_renderer.py: passed; 507 renderer tests passed, three optional local-asset tests skipped; 11 generated scenes passed known-pixel and pooled/isolated equality checks, eight reload projects exercised twice.
- Local packaged scene, Compatibility offscreen: reproduced the missing model, wrong camera and rear-triangle artifacts before the fixes; after, fixed and dynamic camera views show the model and solid ghosts. Four animation samples confirm the jaw opens/closes; a 720-frame path run changes the camera pose with zero script errors.
- Native local-project probe reports Compatibility fallback for dynamic lighting; not a native rendering pass. Two optional text corpus cases remain skipped.
- 1920x1080 offscreen probes retain 176 executed passes/frame and 256,163,584 allocated Vulkan bytes before/after. Shared skeletal playback and parse-once camera curves add authored animation work, not extra passes/targets; sustained desktop performance not measured.
- python3 scripts/build.py --configuration Release: passed; built build/Build/Products/Release/WallpaperMachine.app. No installation, launch, restart, desktop capture, wallpaper change or Parallels control.
- Exact Parallels parity remains unverified without a supplied reference; camera-path zoom/events and camera-cut fades remain unsupported. Existing concurrent shader/parallax edits were preserved and included in shared-tree verification.

## 2026-10-03 — Wallpaper apply and background presentation ordering

- Reproduced the reported interruption with held fake-bridge operations: disabling the serialization fix makes both arrival-order regressions fail with the original interruption error; restored the fix afterwards.
- `python3 scripts/test.py --only WallpaperActivationRecoveryTests` — exit 0; 18 passed, covering Apply/Apply changes versus display refresh, global/per-display suspension, unload/reload and audio suppression, both arrival orders, failure release, cancellation and explicit Pause.
- `python3 scripts/test.py` — exit 0; Python suites passed; native 1070 passed, 12 skipped, 0 failed. Skips: nine real-player media tests, one live SteamCMD install and two live Workshop searches.
- `python3 scripts/build.py --swift-only --configuration Release` — exit 0; built the Release app with existing renderer/bindings, per local build opt-in.
- No desktop control, wallpaper changes, app launch/restart or UI run; visual behavior and private Workshop assets were not verified.
- Existing concurrent renderer/provenance edits were left untouched and were not rebuilt or verified by this Swift-only task.
- `git diff --check` — exit 0; existing documentation paths and commands retained.

## 2026-10-02 — Live Solar System scripted colors and duplicate layer lookup

- python3 scripts/test.py: exit 0; 227 Python tests and 1064 native tests passed, 12 native opt-in tests skipped.
- CMake targeted build: offscreen_scene_probe, scene_schema_tests and script_runtime_compat_test succeeded.
- scene_schema_tests --gtest_filter=SceneSchema.*Duplicate*: 5 passed, including mixed image/group order, module-initialization lookup, independent thisLayer writes and parsing without a runtime.
- script_runtime_compat_test --gtest_filter=ScriptRuntimeCompat.AuthoredColor*:ScriptRuntimeCompat.MaterialConstantUserBindingUpdatesThroughRuntimeProperties: 2 passed; saved color strings stay vectors over repeated ticks and property changes, while text stays a string.
- python3 scripts/check_renderer.py --project <local Live Solar System project.json>: exit 0; 503 C++ tests passed, 3 asset-dependent cases skipped; all 10 generated scenes and the local scene matched pooled/isolated pixels, with 2 successful reload cycles.
- Surface-free Vulkan probes with intro disabled: sun tint changed from black to the authored RGB value, the oversized foreground dwarf planet now receives the simulation scale, and sampled startup and 5.5-second frames had zero script errors.
- The local project retained the same 92 non-cache shader-value diagnostics as the baseline; no new diagnostics. These checks do not establish complete wallpaper compatibility.
- Skipped renderer asset cases: LonelyCatHeadlessRegression, Workshop3409533530FullSceneKeepsClockRenderPassAndTexture and the optional native-Metal local-project test. Live Solar System uses the dynamic-lighting Compatibility path.
- No Release build, app installation/restart, desktop control, screen capture, live audio or Steam sign-in. Desktop interaction and presentation remain unverified.
- python3 scripts/clean.py --dry-run: shared artifacts and other worktree caches were listed, so no shared cleanup was performed. Private probe outputs remain Git-ignored.

## 2026-10-02 — v1.2.3 pre-release gate

- `python3 scripts/build.py --renderer-only` — exit 0; renderer rebuilt and Swift bindings regenerated.
- `python3 scripts/test.py` — exit 0; 227 Python tests passed; native 1064 passed, 0 failed, 12 skipped (9 opt-in media, 3 live network/install).
- `cargo test --release -p wallpaper-bridge --lib` with the build helper environment — exit 0; 367 passed, 0 failed.
- `python3 scripts/check_renderer.py` — exit 0; 24 test binaries and reload cycles passed; all 10 generated pooled/isolated pairs matched with no diagnostics and expected pixels.
- Three asset-dependent renderer cases skipped: two local text-project regressions and the native local-project matrix. No authored-reference compatibility claim.
- `git diff --check` passed; origin/main is an ancestor of the reviewed main, with no unmerged paths. Version dry run: 1.2.2 (24) -> 1.2.3 (25).
- Compiler warnings remain, including Swift concurrency diagnostics and Rust unused-code warnings; zero warnings/issues is not claimed.
- No desktop run, wallpaper change, audio capture, live Steam login, or local Release app build. Release publication will use the Version workflow after the source push.

## 2026-10-02 — Web-only audio capture ownership

- Read-only inspection found the reported web wallpaper registers the standard audio listener; its saved Audio response switch is off. No user settings or private wallpaper assets changed.
- Regression: restoring the old scene-handle-only capture predicate makes capture_tap_follows_web_subscribers_with_no_scene_handle fail; restored the fix before the passing checks.
- cargo test --release -p wallpaper-core --lib: exit 0, 225 passed; cargo test --release -p wallpaper-bridge --lib: exit 0, 367 passed. Controller tests cover one shared tap, external ownership, permission, suspension and rollback; bridge tests exercise the production demand handler, web-only startup and shutdown.
- python3 scripts/build.py --renderer-only: exit 0; generated bindings refreshed without a UniFFI signature change.
- python3 scripts/test.py: exit 0; all 17 Python modules passed; native 1064 passed, 0 failed, 12 opt-in media/network cases skipped.
- python3 scripts/check_renderer.py: exit 0; all ten generated pooled/isolated cases pixel-identical with zero diagnostics, eight reload projects twice; three environment-selected private-asset checks skipped.
- python3 scripts/build.py --configuration Release: exit 0. Local Release app built, not installed or launched.
- Live system capture, actual music reaction, desktop visuals and battery effects remain unverified. No desktop control, windows, screenshots, audio devices or permission prompts used. Existing shared-workspace edits preserved.

## 2026-10-02 — Conditional texture masks contain brightness pulses

- `cargo test -p shader -- --nocapture` (renderer workspace, build environment): exit 0; 504 nominal successes, including 3 asset-dependent early-return skips, not 504 exercised cases. The new SPIR-V/MSL conditional-mask regression failed before the fix and passed after it; existing inactive-default and disabled-texture tests remain green.
- `python3 scripts/check_renderer.py --project <local-scene-project>`: exit 0; 502 native renderer checks passed, 3 optional corpus checks skipped; all ten generated scenes and the affected local scene matched pooled/isolated pixels with no diagnostics; two reload cycles passed. The GPU regression holds masked pixels constant across six alternating brightness frames while unmasked pixels continue changing.
- Surface-free before/after probes: same 30 frames at 1/60 s, fixed seed, untouched local package. Both pulse passes now retain their authored mask slot. Maximum consecutive-frame change in sampled mean red fell from 9.844 to 0.066 code values; both runs executed 540 passes. Masks add their intended texture residency/sampling, not extra passes or lower quality.
- `python3 scripts/test.py`: exit 0; Python modules passed; native gate 1064 passed, 0 failed, 12 skipped.
- `python3 scripts/build.py --configuration Release`: exit 0; local Release app rebuilt under the developer's build opt-in, not installed or launched.
- No desktop control, wallpaper changes, screenshots, audio devices or permissions. Desktop appearance, long-duration visual comfort and live power/frame-time performance remain unverified. Concurrent library/web/bridge/parallax edits were preserved; the gates and build used the shared working tree.

## 2026-10-02 — Workshop presets download and import as self-contained wallpapers

- Cause: Workshop presets (e.g. Purple Ink 1809081988, Ink 3356611918) have no project.json type, only dependency + preset values; validation rejected them.
- Fix: downloader fetches the base in a second SteamCMD pass of the same job; importer assembles base + preset files + merged manifest under the preset id; manual import uses a sibling or installed base.
- python3 scripts/test.py --only ImportTests --only DownloaderLifecycleTests: passed 53, failed 0.
- python3 scripts/test.py: passed 1064, failed 0, skipped 12 (opt-in layers).
- Not verified: a live SteamCMD download of the two real presets (needs Steam sign-in); no Release build.

## 2026-10-02 — Web wallpapers: Chromium-like file:// fetch responses (Unity/WASM)

- Cause: WebKit file:// fetch → status 0/ok false/no Content-Type; Unity 2022.3 wasm streaming + fallback both rejected, canvas stayed dark (Workshop 3756621387).
- Fix: host script serves found file:// GET/HEAD as 200 + extension MIME; served .wasm compiled from bytes (WebKit streaming compiler ~190 ms slower boot).
- Offscreen headless WKWebView repro (no desktop window): before abort('both async and sync fetching of the wasm failed'); after Unity boots, Live2D renders, music loads.
- Perf: 30 MB fetch+arrayBuffer native vs normalized ~68 ms both; Unity boot to first engine log 180 ms (vs 364 ms with native streaming).
- python3 scripts/test.py --only WebWallpaperPageTests/ScreenSaverWebSurfaceTests/WebWallpaperAuthorAPITests: 25 passed.
- python3 scripts/test.py: 1058 passed, 0 failed, 12 skipped.
- Not run: Release build, desktop/visual check of the live wallpaper.

## 2026-10-02 — Video preflight preserves Compatibility fallback (issue #23)

- Reproduction before the fix: python3 scripts/test.py --only WallpaperActivationRecoveryTests/testMatroskaVideoCanBeActivatedWithEitherBackendPreference --only WallpaperActivationRecoveryTests/testMatroskaVideoOptionsCanBeAppliedWithEitherBackendPreference — exit 65; both tests failed with the reported video-decode error on an original silent H.264 Matroska fixture.
- python3 scripts/test.py --only WallpaperActivationRecoveryTests — exit 0; 12 passed, 0 failed or skipped. Covers both apply paths and backend preferences, missing/empty/non-file entries, decoder-error propagation and retry.
- python3 scripts/test.py — exit 0; 227 Python tests passed; native suite 1,057 passed, 0 failed, 12 skipped. Full gate run once after the fix.
- Skipped: nine opt-in native player/media tests, two live Workshop searches and one live SteamCMD install. No media-device or network-test opt-ins enabled.
- Fixture metadata checked with ffprobe: Matroska, H.264, 16 x 16, two video packets, no audio stream; embedded bytes match the generated original. No FFmpeg CLI is required by the regression tests.
- git diff --check — exit 0. No renderer or generated-bridge changes.
- Workshop item 3351864056 is absent locally; its original file and desktop playback remain unverified. No Release build, app launch, install or desktop control performed.

## 2026-10-02 — Single-pass puppet lighting and complete four-light packing

- python3 scripts/test.py: 1064 passed, 0 failed, 12 skipped; 229 Python tests passed. First native attempt was blocked by another build holding the shared Xcode database; retry after it finished passed.
- python3 scripts/check_renderer.py --project <local-scene>: exit 0; 506 renderer tests passed, 3 asset-dependent cases skipped; all 11 generated pixel cases and the private scene matched pooled/isolated output; two reload cycles passed.
- script_runtime_compat_test --gtest_filter=ShaderValueUpdaterCompat.*: 10 passed, including zero-to-five-light color packing and clearing.
- MetalSceneDraw.PuppetEffectsApplyLightingOnceAfterAssembly: all eight original puppet/card, effect/direct, lit/unlit combinations passed across three draws each.
- Negative controls: disabling each fix made its respective new regression fail; restored fixes passed.
- Offscreen private scene: duplicate dimming and eye-patch boundaries removed at startup and a six-second sample. Same three-frame workload retained 197 executed / 40 reused passes and 266389504 allocated GPU bytes; lighting shader work is removed, not replaced with additional passes.
- Existing private scene init TypeError remains, unchanged from baseline. Native local-project probe reports Compatibility because of dynamic lighting; it did not render this scene natively.
- No desktop control, windows, screenshots, wallpaper changes, audio hardware or live services. Desktop appearance/smoothness and power use remain unverified. Concurrent work preserved.

## 2026-10-02 — Macro-sized shader interfaces and nested macro builtins

- Original synthetic shader regressions reproduced unknown COUNT and CAST3 failures before their respective repairs; both now compile SPIR-V and MSL. Numeric combo defaults/overrides and consecutive arrays are covered.
- WALLPAPER_MACHINE_ASSETS_ROOT=<local SceneAssets> cargo test -p shader -- --nocapture: exit 0; 506 reported successful tests, including two unavailable private-asset checks that returned early (504 exercised).
- python3 scripts/test.py: exit 0; Python script suites passed; native verdict 1064 passed, 0 failed, 12 skipped of 1076.
- python3 scripts/check_renderer.py --project <local project>: exit 1 in the shared working tree. All 11 synthetic pixel cases passed; local project pooled/isolated pixels matched and both reload cycles succeeded. The concurrently added MetalSceneDraw.PuppetEffectsApplyLightingOnceAfterAssembly failed; its source and the concurrent parser/updater changes were not modified by this task.
- Surface-free local scene renders restore the sky, mountain and bridge gradients; four formerly rejected gradient effects now compile. Existing dock script errors and a missing layer-texture link remain. Native Metal still refuses the same missing effects/blend image as before, so this scene was verified through Compatibility, not native presentation.
- Changes are shader-compilation-only, with no wallpaper IDs, asset edits or brightness compensation. Restored effects increase the sampled two-frame executed-pass total from 289 to 297 and allocated Vulkan target/image bytes from 244133504 to 278081152; this is authored work previously dropped, not a new correction pass. Desktop performance and exact reference parity are unverified.
- No desktop control, live settings changes, app restart or installation. Eye-square report could not be identified in the bridge scene; screenshot requested. No commit or Release build while the shared renderer gate is failing.

## 2026-10-02 — Layer origin timelines reveal animated intros

- python3 scripts/test.py: passed (1064 native tests, 12 opt-in skips; 17 Python modules).
- python3 scripts/check_renderer.py: passed; 23 test executables, eleven synthetic pooled/isolated pixel comparisons and eight scenes reloaded twice. Two private text cases and the environment-driven local-project case skipped in the default gate.
- scene_schema_tests: 93 passed; script_runtime_compat_test: 85 passed. Origin regressions cover absolute/relative offsets, anchors, missing axes, one loop clock, pause/seek/replay, text/groups, property precedence and relinquishing animation demand.
- MetalSceneDraw.AnAnimatedCurtainRevealsTheWholeCanvasAndStaysOpen: passed for direct and effect-chain layers at initial, intermediate, final and held positions. Compatibility generated-origin-animation independently checks both halves after the curtain exits.
- Installed Into The Abyss [4K]: reproduced the stuck right-side curtain on both backends; after the fix Compatibility at six seconds and Native Metal across 420 frames reveal the full canvas. Native run: 43 render passes/frame, zero blits, 217284608 render-target bytes. These are observations, not a before/after performance benchmark.
- No desktop control, screenshots, wallpaper changes, app restart or audio-device access. Desktop presentation, continuous-playback smoothness and full authored visual parity remain unverified. Concurrent shader/material edits were left intact.

## 2026-10-02 — Correct 2D shader projection and dark lit layers

- Shared LoadMaterial compilation now supplies the authored SCENE_ORTHO value, including effect passes; no brightness multiplier or wallpaper-specific code.
- Original Metal pixel regression covers both projections, direct/effect rendering and unlit colours; passes with the fix and fails with it removed.
- python3 scripts/check_renderer.py with the affected local project: exit 0; all ten generated cases and the local scene have identical pooled/isolated pixels, no diagnostics, and reload cycles pass.
- Renderer asset-dependent cases: two text fixtures and the environment-selected native-project test skipped. The separate native probe reports the affected scene's existing dynamic-lighting fallback to Compatibility.
- Before/after Compatibility probe: 366 executed passes and 845691008 allocated GPU bytes in both runs; restored brightness inspected only in private offscreen frames.
- python3 scripts/test.py: exit 0; Python modules pass, native gate reports 1064 passed, 0 failed, 12 skipped.
- Desktop presentation and exact authored-light parity unverified. Existing PerformLighting_V1 approximation unchanged; no desktop, audio hardware, live library changes or app restart.
- Unrelated concurrent renderer edits appeared during verification; leave them unstaged and defer the Release build rather than package unfinished shared-workspace changes.

## 2026-10-02 — Keep Discover responsive without canvas preview readback

- Live diagnostics: the native main thread remained in its event loop while WebKit logged RemoteImageBuffer_FlushContextSync failure and repeated 15-second FillRect/DrawNativeImage waits. No desktop control or restart was performed.
- Regression red check: python3 scripts/test.py --only ControlPanelDiscoverTests/testDiscoverPreviewsPlayWithoutCanvasReadbackAndReleaseOffscreenImages — failed on the old implementation; 33 canvas requests and neither loaded animation revealed with canvas unavailable.
- python3 scripts/test.py --only ControlPanelDiscoverTests — exit 0; 6 passed, 0 failed, 0 skipped. Covers loaded dark/bright previews without canvas, error fallback, still-first loading, hidden/offscreen release and cached resume.
- python3 scripts/test.py — exit 0; all 17 Python modules passed; native 1064 passed, 0 failed, 12 skipped (3 live-network and 9 opt-in media tests).
- python3 scripts/build.py --swift-only --configuration Release — exit 0; bundled panel.js matches source and codesign --verify --deep --strict passes.
- No renderer changes in this fix; concurrent renderer edits were left untouched. No live GPU-hang reproduction or desktop visual check; installed app not replaced or restarted.

## 2026-10-01 — Sync main download fixes with remote SteamCMD and lock-screen fixes

- Merged origin/main without rewriting existing commits; regenerated the Xcode project with xcodegen generate and preserved both sides of verification history.
- python3 scripts/test.py — passed; 1053 native tests passed, 0 failed, 12 skipped of 1065; all Python test suites passed.
- Uncommitted frame-rate slider changes were stashed and excluded from this gate and merge.
- No desktop run, live Steam sign-in/install, renderer corpus check, or Release build; this was a repository synchronization.

## 2026-10-01 — Steam and pixiv failure diagnosis

- Fixed unknown SteamCMD failures being attributed to credentials; classify compact network/rate-limit result names and log only a safe category.
- pixiv HTTP 403 now explains access denial rather than promising a one-minute wait; HTTP failures log status only, without URLs, cookies or bodies. Updated all four native locales.
- python3 scripts/test.py --only SteamCMDReportedFailureTests --only DownloaderLifecycleTests --only PixivServiceTests: passed 55, failed 0, skipped 0.
- First python3 scripts/test.py: Python passed; native 1036 passed, 1 failed, 11 skipped. WallpaperImportPickerTests/testCancellationReapsThePickerWaitingForASelection exceeded 120 seconds; no picker code changed.
- python3 scripts/test.py --only WallpaperImportPickerTests: passed 5, failed 0, skipped 0; timeout did not reproduce.
- Final python3 scripts/test.py: all 244 Python tests passed; native 1037 passed, 0 failed, 11 skipped (9 opt-in media tests, 2 live Steam tests).
- python3 scripts/build.py --swift-only --configuration Release: succeeded; app not launched or installed.
- The reported user's root cause remains unconfirmed without their diagnostics/network details. No live Steam login, live pixiv access or visual/desktop checks; unrelated workspace edits preserved.

## 2026-10-01 — PR 22 integration with current main

- Merged origin/main at e1fc9e1 into the native SteamCMD PR without rewriting history. The only conflict was the verification log; replayed the two PR-only entries through log_verification.py and asserted that both branches’ historical entries were preserved exactly, with ten active entries.
- `python3 scripts/test.py --only SteamCMDSetupTests --only SteamCMDApprovalTests --only LockScreenWallpaperServiceTests` — exit 0, 91 passed, none skipped.
- Full `python3 scripts/test.py` in the logged-in Aqua session — exit 0; 226 Python tests and 1,047 native tests passed, 12 opt-in skips. Ran the full gate once on the integrated tree.
- Skipped: nine opt-in media tests, two live Workshop-page cases and the live SteamCMD installer. No renderer/corpus, live account/CDN or desktop checks; no Release rebuild or production app restart.
- Resolved in the isolated PR worktree, leaving unrelated original-checkout edits untouched. git diff --check and staged conflict-marker checks passed.

## 2026-10-01 — PR 22 redirect-failure review fixes

- Addressed CodeRabbit and Claude: preserve a rejected redirect’s original failure if URLSession delivers its final response before cancellation; retain the isolated Foundation configuration copy with a narrowly documented SwiftLint force_cast suppression.
- Regression-first check: `python3 scripts/test.py --only SteamCMDSetupTests/testRejectedRedirectRetainsItsFailureWhenFinalResponseArrivesBeforeCancellation` failed before the fix by comparing original versus overwritten error values. It pins no localized wording and uses only URLProtocol fixtures.
- `python3 scripts/test.py --only SteamCMDSetupTests` — exit 0, 41 passed. Full `python3 scripts/test.py` in Aqua — exit 0, 226 Python tests and 1,042 native tests passed, 12 skipped; full gate ran once.
- Skipped: nine opt-in media tests, two live Workshop-page tests and the live SteamCMD install. No live account/CDN, renderer/corpus or desktop checks were run for this small download-delegate fix. SwiftLint is unavailable locally; its suppression was not verified with the lint executable.
- Verification ran on PR 22’s branch in an isolated worktree, leaving concurrent edits in the original checkout untouched. Coverage docs updated; git diff --check clean. No Release rebuild, production app launch/restart, security-setting changes or history rewrite.

## 2026-10-01 — Native Apple silicon SteamCMD package installation

- Full gate: `python3 scripts/test.py` in the logged-in Aqua session — exit 0; 226 Python tests and 1,041 native tests passed, 12 native tests skipped. Ran the full gate once.
- Gate skips: nine opt-in media cases, two live Workshop-page cases, and the opt-in SteamCMD install. Renderer/corpus and desktop/visual checks were not run; no renderer code changed.
- Targeted approval/runtime/downloader/queue/telemetry/WorkshopStore/ControlPanelShell runs with `python3 scripts/test.py --only …` — exit 0, 112 passed; remaining six ControlPanel classes — exit 0, 30 passed.
- `WALLPAPER_MACHINE_NETWORK_TESTS=1 python3 scripts/test.py --only SteamCMDSetupTests --only SteamCMDLiveInstallTests` — exit 0; 41 passed (40 offline setup regressions plus the live native installation), none skipped.
- Live install used temporary support/preferences/approval directories, real CDN packages, per-slice codesign and spctl, and the real native runner. Ready, arm64 resolution and Loading Steam API...OK were asserted; nothing installed into the user’s SteamCMD directory.
- Live checks exposed and fixed HTTP gzip Content-Length versus decoded-byte accounting and quarantined smoke exec being killed. Smoke now uses the downloader’s existing validated disposable-copy path; the installation candidate remains quarantined and policy failures are not bypassed.
- `spctl --assess --type execute --verbose=2` on the quarantined temporary native runtime returned 3 with valid-but-not-an-app, not the earlier sandbox’s internal error. All Mach-O slices verified and steamcmd satisfied Valve’s signing requirement; no system security settings changed.
- Authorized cached-session checks, using copied files and `arch -arm64`: sign-in without secret input, an active license listing app 431960, Workshop item 3773084716 downloaded successfully, and Windows app_update reached downloading then its owned process group was stopped. Temporary session copies were deleted, never written back.
- Localization: all ten changed native keys cover en/ja/zh-Hans/zh-Hant; panel localization passed in the gate. WebUI mechanical detector reported no findings; reinstall confirmation flow was inspected without desktop interaction.
- Owning feature/testing docs updated; Xcode project regenerated by test.py; git diff --check clean. Remaining risks: Valve changing/removing the package manifest and Intel-only copies needing reinstall. No Release rebuild, app launch/install/restart, wallpaper changes, or commit.

## 2026-10-01 — Preserve committed display mapping across lock-screen retry

- The reported timeout → missing display UUID → lock Retry → saver Off transition now invalidates only the lock request cache key, retaining the committed mapping needed for immediate Idle restoration.
- python3 scripts/test.py --only LockScreenWallpaperServiceTests --only LockScreenWallpaperTests — exit 0; 80 passed, 0 failed, 0 skipped. Includes pending lock recovery after the UUID returns without re-enabling the saver.
- python3 scripts/test.py — exit 0; 226 Python cases across 17 modules; native: 1036 passed, 0 failed, 11 skipped of 1047.
- Runtime smoke — temporary CLI linked current production Debug objects without the app entrypoint. With a software-generated silent video and isolated defaults/store, the missing-UUID transition restored original Idle immediately and removed the journal; exit 0. Temporary scaffolding removed.
- Owning feature and coverage documentation updated; relative links checked. No real WallpaperAgent reload, desktop changes, app launch, visual or power verification, or Release rebuild.

## 2026-10-01 — Keep screen saver selected when restored lock-screen activation times out

- Before fix: the restored-preferences regression failed (0 passed, 1 failed); after fix: all 33 LockScreenWallpaperServiceTests passed. The extra LockScreenWallpaperSelectionTests selector matched no class; the full gate below covered LockScreenWallpaperTests.
- python3 scripts/test.py — exit 0; all 17 Python test modules passed; native: 1035 passed, 0 failed, 11 skipped of 1046. Skips: 9 opt-in native-player media cases and 2 live Steam searches.
- Runtime smoke — temporary CLI linked the production Debug service/selection objects without the app entrypoint. A software-generated silent video, isolated defaults and wallpaper-store files exercised timeout retention, saver pause updates, lock disable and exact shutdown restoration; exit 0.
- Shared extension incompatibility, failed Idle-only publication, stale readiness and a later saver renderer failure remain covered by regression tests.
- No real WallpaperAgent reload, desktop changes, app launch, visual lock/idle transitions, or power measurements. The OS cause of the reported post-update missing lock-screen acknowledgement remains unverified; no Release rebuild requested.

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

## 2026-10-01 — PR 19 backup and preset review fixes

- `python3 scripts/build.py --renderer-only` — passed; rebuilt the isolated worktree’s missing current bridge library and regenerated unchanged bindings after the first targeted run could not link.
- `python3 scripts/test.py --only WallpaperBackupTests --only WallpaperPresetStoreTests --only ControlPanelBackupFlowTests` — passed, 50 tests; an earlier run exposed volatile-default cleanup in the new fixture, corrected before this run.
- `python3 scripts/test.py` — passed once as the final gate: all Python checks passed; 1006 native tests passed, 0 failed, 11 opt-in media/network cases skipped.
- Regressions cover persistent-only preference export/conflicts/rollback, a 48 MiB preset archive, manifest rejection before payload reads while preserving an existing destination, and preset directory roundtrips with hidden Finder metadata.
- The WebUI mechanical detector reported no findings; `git diff --check` passed. No renderer source or generated-binding changes.
- No Release app build, desktop/window-driving, visual presentation, audio hardware or live-account verification. The shared main checkout’s existing commit and uncommitted edits were not changed.

## 2026-10-01 — Reusable wallpaper workflows rebased onto 1.2.1

- Implementation: local collections and named playlist plans, wallpaper property presets, staged local backup/restore, per-display still-image placement, compatibility cards, Shortcuts display selection, and Web page mute/native HTML-media gain; all four UI languages updated.
- Fetched origin and rebased feat/library-workflows-and-web-audio onto main a5200fe; preserved remote import-picker startup, screen-saver/renderer updates, localization and historical verification records. Regenerated Xcode project and UniFFI outputs rather than editing generated conflicts.
- Scene restore security: scene/scenetexture overrides and texture defaults now resolve to validated retained image files instead of unapproved original paths. A keep-existing tree without matching bytes is rejected before publication. WallpaperBackupTests: 24 passed before rebase; included again in the rebased full gate.
- python3 scripts/build.py --renderer-only — exit 0 after rebase; renderer library and Swift bindings regenerated. No Release app build.
- cargo test -p wallpaper-bridge with scripts/build.py cargo_environment — exit 0 after rebase; 363 passed, 0 failed.
- python3 scripts/check_renderer.py — rebuilt current renderer probes, exit 0; 10 generated scene pixel comparisons and 8 projects x2 reload cycles passed. Three local-asset-dependent cases skipped; no full authored-wallpaper compatibility claim.
- python3 scripts/test.py — exit 0 after rebase; all Python checks passed, 1002 native tests passed, 0 failed, 11 opt-in media/network tests skipped of 1013.
- Before rebase: six temporary real offscreen WKWebView feature flows passed and were removed after retaining focused regressions; renderer draft/metadata and synthetic pointer-capture boundaries were injected. Native WebKit output probe invoked media gain and read back mute false→true→false without audio hardware.
- Desktop/visual presentation, actual speaker output, live account services, Siri/Shortcuts UI and power remain unverified. No app launch, permission prompt, wallpaper change, install or restart.

