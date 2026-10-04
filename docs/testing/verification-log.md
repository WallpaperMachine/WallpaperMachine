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

## 2026-10-03 — Software-decoded video GPU import

- Reproduced the initial GPU-import failure in the installed reported video, read-only, using playback_gpu_test --gtest_filter='DecodedFormats/*:AppleVideoFrame.LocalVideoImportsVisiblePixels' with WE_TEST_VIDEO. All five cases failed before the allocation fix and passed afterward.
- Generated BGRA, NV12, YUV420P and YUVJ420P cases verify exact strided color/alpha pixels after decoder-buffer release, with no conversion destination or CPU GPU-wait added by import.
- The local clip's first decoded frame imported successfully afterward: 667163 of 921600 pixels exceeded the visible-pixel threshold. This checks GPU texture import, not desktop presentation or authored-reference equivalence.
- python3 scripts/test.py: exit 0; Python modules passed; native tests 1156 passed, 0 failed, 12 opt-in skips.
- python3 scripts/check_renderer.py: exit 0; all 30 registered binaries passed; 12 generated pooled/isolated cases matched with expected pixels and no diagnostics; eight projects reloaded twice.
- Renderer skips: two asset-dependent text cases, one local-project Metal case, and WE_TEST_VIDEO unset in the routine gate. The video diagnostic was run separately with the reported clip; skipped asset cases are not claimed as passing.
- python3 scripts/build.py --configuration Release: exit 0; Release app built, not launched or installed.
- No wallpaper assets, settings, hardware-decoder selection or frame scheduling changed. No desktop control, screenshots or audio hardware; desktop appearance, sustained playback and energy impact remain unverified.

## 2026-10-03 — PR 25 merge with audited main

- Merged `origin/main` at `d895d74` without rebasing; preserve the audit registry/GPU prerequisites, all 12 synthetic scenes, both regression sets, and all 42 distinct historical verification entries.
- Reconciled stage-interface bounds with the audit leading-macro undefinition/redefinition behavior; the new unit regression passed.
- `python3 scripts/build.py --renderer-only` — passed; renderer rebuilt and bridge bindings regenerated, matching the incoming generated files. No Release app build.
- `python3 scripts/check_rust.py` — all four suites exited zero: core 223, bridge 378, core integration summaries 15, shader 533 reported passed; shader reports three unavailable corpus early-return skips.
- Rust exclusions remain explicit: two desktop window tests and four external-corpus tests; desktop/media/network opt-ins disabled.
- `python3 scripts/check_renderer.py` — all registered binaries passed; all 12 synthetic pooled/isolated pairs matched with zero diagnostics; eight projects completed two reload cycles.
- Additional C++ suites rebuilt and passed in isolated state: scene_schema_tests 108, script_runtime_compat_test 91, mouse_input_test 13.
- `python3 scripts/test.py` — all Python suites passed; 1,156 native passed, zero failed, 12 skipped. Renderer-tooling targeted suite: 17 passed.
- Renderer corpus skips: two local text scenes and the environment-selected Metal project case. No desktop visual/live keyboard validation, authored-reference parity claim or app launch.
- `git diff origin/main --check`, regenerated-binding consistency, historical-entry preservation/order and conflict-marker checks passed; incoming generator whitespace was not hand-edited.

## 2026-10-03 — PR 24: retry eligibility and durable pixiv cancellation

- Web host state now explicitly grants retry only to failures from the current live page; panel rendering, action dispatch and host retry all honor that capability.
- Project validation and fingerprint failures remain visible without an ineffective retry action, including failures while an older surface still exists.
- Pixiv cancellation is excluded from the durable queue immediately while the task retains its slot until cleanup finishes; pause/shutdown cannot revive cancellation, and a fresh request discards orphaned partial data.
- python3 scripts/test.py --only WebWallpaperHostLifecycleTests --only ControlPanelHostStateTests: 9 passed, 0 failed/skipped. Initial test compile error in an error-pattern catch was corrected before this successful run.
- python3 scripts/test.py --only PixivDownloadQueueTests: 9 passed, 0 failed/skipped; held cancellation cleanup covers queue restore, slot ownership, shutdown, paused checkpoints and fresh enqueue.
- python3 scripts/test.py: 256 Python tests and 1148 native tests passed; 0 failures and 12 media/network opt-in skips. Full gate ran once after both changes were final.
- git diff --check passed. No renderer/bridge changes, so renderer checks and binding generation were not repeated.
- No Release app build, desktop automation, live pixiv/Steam access or real media-hardware validation. Panel assertions use offscreen fixtures.

## 2026-10-03 — PR 24 review follow-up

- Addressed all 12 inline review threads: per-wallpaper purge isolation, resume consent, benchmark schema lookup, effective-cap reporting, artwork validation, dangling symlinks, BGRA admission, encoder skips, allocator scope, termination order, checkpoint recovery and empty playback notifications.
- python3 scripts/test.py --only UserAssetStoreTests --only WorkshopStoreTests --only WorkshopDownloadPersistenceTests: 55 passed, 0 failed, 0 skipped.
- python3 -m unittest scripts.tests.test_power_benchmark scripts.tests.test_mediaremote_stream: 38 passed, including synthetic startup/track callbacks; no real player access.
- Targeted cargo test --release --locked --lib checks: wallpaper-bridge tests::quality_settings (10), tests::web_audio_media (21), wallpaper-core tests::general::shader_cache (5); all 36 passed with isolated WALLPAPER_MACHINE_HOME.
- python3 scripts/build.py --renderer-only: passed and regenerated bindings, with no generated API changes; no Release app build.
- python3 scripts/test.py: 256 Python tests and 1143 native tests passed; 0 failures, 12 native media/network opt-in skips. The new WorkshopDownloadIntentTests resume-consent case passed in this full gate.
- python3 scripts/check_renderer.py: passed with GPU checks executed; all 10 generated pooled/isolated pairs matched with zero diagnostics, expected pixels passed, and 8 projects completed two reload cycles each.
- Renderer gaps: three local-asset cases skipped; the existing disabled JPEG timing benchmark was not run. Desktop, visual presentation, live Steam, real media hardware and battery/power behavior were not exercised.
- git diff --check and all auditRemediation provenance SHA-256 checks passed; CLAUDE.md remains a relative AGENTS.md symlink. Changes remain local, uncommitted and unpushed.

## 2026-10-03 — Audit remediation across app, renderer and tooling

- Completed all 79 formal audit findings; the excluded/withdrawn audit candidates were not promoted into the repair scope. Owning feature/testing docs and 106 changed upstream file hashes are recorded.
- python3 scripts/build.py --renderer-only: exit 0; Rust/C++ renderer dependencies rebuilt and UniFFI bindings regenerated. No Release application build or delivery.
- python3 scripts/test.py: 254 Python tests passed; native 1140 passed, 0 failed, 12 skipped of 1152. First attempt stopped at catalog quote-format validation; fixed and full gate passed on retry.
- python3 scripts/check_renderer.py: exit 0; 662 gtests passed, 3 external-corpus tests skipped; 10 generated scene pixel comparisons and 16 reload cycles passed. Fixed one missed probe API migration and an obsolete prepared-state fixture before final success.
- python3 scripts/check_rust.py --output artifacts/remediation-20261003/rust-final: all four groups exit 0; core 223, bridge 377, integration 15 plus layer pixel executable, shader 529 reported including 3 corpus early-return skips. Two desktop and four corpus cases explicitly excluded.
- Focused regressions cover asset commit/cancel/rollback interleavings, same-path content refresh, host readiness/audio delivery, durable download pause/resume, updater cancellation/ownership, media withdrawals and failed extension-surface reuse. Security boundary candidate received independent source review; no new confirmed regression.
- Synthetic Debug measurements: 10000-row snapshot construction 35.70 ms initially versus 1.94 ms mean progress update; actual payload JSON UTF-8 2303731 to 5935 bytes. Asset cold preparation for 8/128/1024 files kept measured main-actor maximum delay below 7 ms; timings are observations, not whole-app energy claims.
- arm64 JPEG scalar/NEON output was byte-identical; decoder-only warm medians improved about 33%. Runtime GPU checks used private images. Desktop/UI opt-ins, live account/network/player tests and missing external corpus checks were not run; UI source typecheck passed.
- git diff --check passed for handwritten sources; generated UniFFI formatting retains generator whitespace. CLAUDE.md remains the relative AGENTS.md symlink. No commit, push, app install/restart or desktop interaction.
