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
