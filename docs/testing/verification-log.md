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

## 2026-10-03 — PR 25 Claude review follow-ups

- Unified stage-interface array bounds for location allocation and emission; unsupported expressions, late/missing definitions and nonpositive sizes now fail explicitly.
- Single-sample alpha-to-coverage uses source-over blending on Metal/Vulkan; multisampled state retains unblended coverage without adding targets or passes.
- `cargo test -p shader -- --nocapture` using the project Cargo environment — exit 0; 507 reported passed, including three unavailable asset-dependent early-return skips.
- `python3 scripts/check_renderer.py` — exit 0; all 12 synthetic pooled/isolated pairs matched with zero diagnostics; eight projects completed two reload cycles. All recorded test binaries exited zero.
- Negative control: the preceding renderer binary fails the new single-sample composed-coverage pixel assertion; the rebuilt renderer passes. Native Metal transparent/half/opaque pixel regression also passed.
- `scene_schema_tests --gtest_filter="SceneSchema.*Camera*:SceneSchema.PerspectiveFallback*"` after rebuilding — 19 passed, including steep/rolled look-at, scaled/zero deltas and fallback registration.
- `python3 scripts/test.py` — all Python suites passed; 1,072 native passed, zero failed, 12 skipped. Existing cancellation/preview-error tests and new offscreen Tab/Shift-Tab wrapping passed.
- Stable-sorted verification entries by date through the log helper functions, preserving every historical body and relative archive link; new evidence appended only via `scripts/log_verification.py`.
- Asset gaps: three shader corpus cases, two local text scenes, and the environment-selected Metal project case skipped. No desktop visual/live WebKit keyboard check, authored-reference parity, app launch or Release rebuild.

## 2026-10-03 — PR 25 merge conflict resolution

- Merged `origin/main` into `fix/scene-playback-panel-shaders` without rebasing; retained both sides of renderer provenance and all 36 distinct historical verification entries.
- `python3 scripts/test.py` — all Python suites passed; native results: 1,071 passed, zero failed, 12 skipped.
- `python3 scripts/check_renderer.py` — exit 0; all 11 synthetic pooled/isolated comparisons matched with zero diagnostics; eight projects completed two reload cycles.
- Built `scene_schema_tests` and `script_runtime_compat_test` with the project build environment; 26 targeted duplicate-name/parallax/camera/model tests and two color/composition tests passed.
- Targeted coverage includes both incoming regressions: duplicate names retain independent bindings, and authored color properties remain vectors across updates.
- Renderer asset gaps remain: two local text-scene tests and the environment-selected local-project Metal test skipped; no authored-reference parity claim.
- Provenance JSON, historical-entry preservation, conflict-marker checks, and `git diff --check` validated before commit.
- No desktop automation, visual validation, app launch, or Release app rebuild performed.

## 2026-10-03 — Shader macro fixes and pending scene/playback/panel PR

- `python3 scripts/test.py` — passed: 1,071 native tests passed, 12 skipped; all Python script suites passed.
- `cargo test -p shader -- --nocapture` from `upstream/renderer`, using `scripts/build.py` cargo environment — exit 0; 506 reported passed, including three asset-dependent early-return skips.
- Shader corpus gaps: two auto-sway/depth-parallax fixtures and the genericimage4 asset case were unavailable; those cases are skipped, not verified.
- New macro-sized varying and nested legacy macro regressions passed for SPIR-V and MSL.
- `python3 scripts/check_renderer.py` — exit 0; all 11 synthetic pooled/isolated pairs matched with zero diagnostics; eight projects completed two reload cycles.
- Renderer gaps: two local text-scene cases and the environment-selected local-project Metal case skipped; no authored-reference parity claim.
- `git diff --check` — passed before commit.
- No desktop automation, visual validation, app launch, or Release app rebuild performed.

## 2026-10-03 — Tile layer textures, unblended alpha-to-coverage, random sprite frames

- Composite render targets follow the source layer clampuvs; alphatocoverage writes kept samples unblended on both backends; randomframe particles get a fixed hashed per-particle frame. No wallpaper-specific rules, MSAA, extra passes or allocations.
- Targeted: layer_texture_reference_test 20, particle_mouse_controlpoint_test 42, metal_backend_test 35, scene_schema_tests 100 passed.
- python3 scripts/check_renderer.py: passed; 509 renderer tests, 3 optional local-asset skips, 0 failures; 11 generated scenes pass pixel and pooled/isolated checks; 8 reload projects x2.
- python3 scripts/test.py: passed; 1,071 native passed, 12 skipped.
- Local packaged 3D scene, Compatibility offscreen, disposable package copies forcing single camera paths: the solid blue planes came from a 497x-tiled maze composite sampled with clamp; after the fix the maze tiles and sprite particles show varied frames.
- Remaining against the supplied Windows screenshot: maze lines are thinner/dimmer (single-sample coverage threshold vs likely MSAA) and distant lines alias; not changed, to avoid MSAA memory/perf cost.
- python3 scripts/build.py --configuration Release: passed. No desktop capture, Parallels inspection, wallpaper change or app launch.

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
