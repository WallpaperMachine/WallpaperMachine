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

## 2026-10-01 — Sync main download fixes with remote SteamCMD and lock-screen fixes

- Merged origin/main without rewriting existing commits; regenerated the Xcode project with xcodegen generate and preserved both sides of verification history.
- python3 scripts/test.py — passed; 1053 native tests passed, 0 failed, 12 skipped of 1065; all Python test suites passed.
- Uncommitted frame-rate slider changes were stashed and excluded from this gate and merge.
- No desktop run, live Steam sign-in/install, renderer corpus check, or Release build; this was a repository synchronization.
