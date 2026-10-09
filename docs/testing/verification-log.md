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

## 2026-10-09 — Keep web wallpapers animating through Show Desktop pointer moves

- Symptom: a web wallpaper (3747222633) froze briefly on every hot-corner Show Desktop; scene wallpapers did not. Unified logs showed no host suspension, WebKit activity-state change or poster capture at those moments.
- Before evidence (installed v1.3.2, three Show Desktops, 3 s sample of app/WebContent/GPU each): app main thread spent 122/234/210 ms in NSWindow.windowNumber(at:) via SLSCopyWindowRoutingRecordsForScreenLocation from WebWallpaperMouseForwarder, 0 ms in the idle baseline; WebContent updateRendering samples fell 20–45% in the same windows.
- Fix: routing reads the window the window server recorded in the event (kCGMouseEventWindowUnderMousePointer); only a press or scroll without it still queries, a move without it is dropped.
- Hand probe on real global-monitor events: field 91 matched windowNumber(at:) in 1536 of 1540 events (4 were transient screenshot-tool windows), never 0. Field 92 skipped the menu bar for moves, so it was not used. No scroll events were captured.
- python3 scripts/test.py --only WebWallpaperMouseRoutingTests: 6 passed (2 new); synthesized scroll events do not keep the field, so scrolls are covered by the fallback test.
- python3 scripts/test.py: 267 Python tests passed; native 1315 passed, 0 failed, 14 skipped of 1329. Full gate run once.
- Gap: smoothness after the fix on the real desktop is not yet measured; the same capture script must be re-run against a build that contains it.
- Separate, unfixed: a web page assigned while its display is suspended loads detached, so its first reveal is a cold start (327 ms hidden content plus shader compiles on 2026-10-09 18:03:57).

## 2026-10-09 — v1.3.2 published release and import-helper recovery

- Published [v1.3.2](https://github.com/WallpaperMachine/WallpaperMachine/releases/tag/v1.3.2), build 31, from `e278ae8f205e324835facd6f84c70e27f3d31cc7`; [Version run 37825423704](https://github.com/WallpaperMachine/WallpaperMachine/actions/runs/37825423704) passed every required job. Failed, unpublished v1.3.0/v1.3.1 tags were preserved; notes cover v1.2.6 through v1.3.2.
- Import-helper repair `8fb411a`: six targeted child-process tests passed normally and with `TEST_RUNNER_LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`. Local `python3 scripts/test.py` passed 268 Python and 1,313 native tests, with 14 skips; no desktop picker was opened.
- CI `python3 scripts/test.py --serial` passed 268 Python and 1,312 native tests, with 15 skips and no failures. Rust core, bridge, core-integration and shader checks passed; six explicit desktop/corpus exclusions and three missing-asset shader skips remain unverified.
- CI renderer checks passed 12 generated pixel comparisons and eight projects through two reloads. Seven asset-dependent cases were skipped. The compiled timer probe exited 77 (35.20 ms median for a 10 ms wait), so ten named wall-clock cadence cases were skipped under `--allow-imprecise-timers`; these skips are not passing runtime coverage.
- CI verified the Release bundle and mounted disk image. Independently downloaded the public DMG: 36,496,549 bytes, SHA-256 `abaa683f21d1c24e97f8eb6f8c08839e9ba1bc0a4b573b893ea1d4258af47e32`; it matches the CI artifact, public sidecar, release asset metadata and public latest update manifest.
- Release body matches the tagged English notes and `Built from` commit; bundled changelog contains English and Simplified Chinese. Latest resolves to v1.3.2 and equals the highest public stable version. Public DMG and manifest requests succeeded.
- `gh attestation verify` passed for the public DMG, restricted to this repository and `.github/workflows/build.yml`, rejecting self-hosted runners and enforcing source digest `8fb411a34d05dc1a3f4218afaa1d647bc9d94089`. As documented, this event digest precedes the version-bump commit; `Built from` records the built revision.
- No install, launch/restart, desktop/Spaces/Mission Control/VoiceOver, real Siri/Focus, or manual disk-image smoke was performed. CI packaging and headless checks do not verify those surfaces. The release remains self-signed, not Developer ID signed or notarized.

## 2026-10-09 — Release recovery after hosted test timing failures

- v1.3.0 was tagged but not published: attempt 1 failed an onboarding test that counted incoming snapshots as requests; attempt 2 failed ThreadTimerTest.RequestsAfterALongWaitStillRespectTheCeiling on a host whose timer probe returned 77.
- Test-only welcome replay fix `5ff25f1` now checks outgoing actions and injects an unrelated snapshot. Application code remains unchanged.
- Added the omitted 50 ms cadence test to the existing exact-name CI fallback, only after the compiled timer probe reports imprecise timers. Default local runs still execute it; other failures remain failures.
- Version workflow accepts optional notes_from, passed as release_notes.py --previous, so a new patch after an unpublished failed tag can include all changes since the last public release. Tags and live releases are not rewritten.
- Python renderer/version/release-notes suites: 106 passed. Workflow shell arguments verified for default and explicit previous tag; developer preview includes the unpublished feature commits from v1.2.6.
- Full local gate: 268 Python and 1,312 native passed, 0 failed, 14 skipped; artifacts/tests/Tests-20261009-012014-576231.xcresult (disposable).
- First local renderer pass hit the time-sensitive UnchangedPresent frame-order assertion. Separate rerun python3 scripts/check_renderer.py --skip-build passed, with realtime_checks_executed=true, 12 equal pixel comparisons and 8 x 2 reloads; four asset checks skipped. Evidence artifacts/renderer/adaptive-20261009-012147 (disposable).
- No runtime implementation, desktop interaction, installation, first-launch or manual-smoke changes. Recovery publication is tracked separately and must still pass the CI gate.

## 2026-10-09 — Integrate Mission Control refreshes with Space-scoped posters

- Integrated upstream `dc6b764` (Mission Control refresh/settling, injected-clock downloader tests and Supporter list) with feature commit `81eb112`; preserved both histories without rebase or force.
- Kept JPEG encoding, changed-frame deduplication, immediate/3 s/15 s/optional 5-minute captures and lock-screen settling while retaining per-Space request contexts and scoped poster ownership.
- Added regressions proving settling/periodic requests use the current Space context and respect hold, and identical pixels are reused on another Space only after a fresh context is confirmed.
- Targeted desktop/native-video/Space/scheduler/lock-screen-authority/downloader tests — 129 passed, 0 failed, 0 skipped.
- `python3 scripts/test.py` — exit 0; 268 Python tests passed; native 1,312 passed, 0 failed, 14 skipped of 1,326. Full gate ran once for this integration.
- Native evidence: `artifacts/tests/Tests-20261009-001715-304824.xcresult` and same-name `.log` (disposable local evidence).
- Renderer/bridge source is unchanged from the feature commit; the prior renderer-only build and 12 pixel comparisons plus 8 x 2 reloads remain applicable. Four asset checks were skipped, not passing asset coverage.
- All 64 pre-existing verification entries from both merge parents were retained using the verification-log script; the active log remains bounded to ten entries. Diff and agent-path checks passed.
- No real desktop/Mission Control/Space transitions, visible UI, VoiceOver, Release app rebuild or install/restart was performed. User authorized commit and push; remote delivery is checked separately after this commit.

## 2026-10-08 — Lock-screen desktop settles before holding a frame

- Report: AbyssGaming【琉璃】 left Mission Control Space thumbnails black with Animate lock screen on; DesktopPosters was empty (poster sync suspended, extension owns Desktop).
- Root cause: offscreen_scene_probe, 21 frames at 1 s steps: frame 0 mean brightness 0.0, 67.8 at 1 s, ~122-135 from 2 s on. The extension held its readiness frame.
- Fix: WallpaperPresentationAuthority.desktopSettleBudget (15 s) keeps an unlocked lock-screen surface animating after its first frame; on pausing it reads the held frame back for snapshots/backing.
- python3 scripts/test.py --only WallpaperPresentationAuthorityTests: 16 passed. python3 scripts/test.py: 1215 passed, 0 failed, 14 skipped.
- Not checked: real Mission Control thumbnails with the extension; whether WallpaperAgent re-reads the extension snapshot after it pauses.

## 2026-10-08 — Mission Control poster refresh

- Change: desktop poster retaken 3 s and 15 s after a new/changed/resumed wallpaper, fresh capture on Space change and wake, unchanged frames skipped by pixel digest, JPEG (q0.9) instead of PNG, optional 5-minute refresh in Settings › General.
- Encode cost measured on M5 Pro at 3456x2234: PNG ~215 ms / 8.9 MB, JPEG ~32 ms / 2.8 MB, HEIC ~40 ms / 2.3 MB (synthetic graded frame).
- python3 scripts/test.py --only DesktopWallpaperTests --only PlaybackPreferencesTests: 49 passed.
- python3 scripts/test.py: 1214 passed, 0 failed, 14 skipped (opt-in layers).
- Not checked: real Mission Control thumbnails, WallpaperAgent caching of replaced pictures, the lock-screen-provider mode (unchanged; still a frozen frame). Needs the manual-smoke Mission Control steps.

## 2026-10-08 — Desktop Space choices and scoped poster ownership

- Added experimental Follow desktop Space automation: per-display UUID choices for wallpapers/playlists, persistent visit identities, manual overrides until the next regular desktop visit, fullscreen exclusion, Focus priority and animated-lock-screen conflict checks.
- `python3 scripts/build.py --renderer-only` — exit 0; rebuilt the renderer static library and regenerated bindings for the Objective-C++ poster context change. No Release app bundle was rebuilt or delivered.
- `python3 scripts/test.py` — exit 0; 268 Python passed; native 1,305 passed, 0 failed, 14 skipped of 1,319. Full gate ran once in this batch. Native evidence: `artifacts/tests/Tests-20261008-235505-811159.xcresult` and same-name `.log` (disposable).
- Targeted monitor/scheduler/store/poster/native-video/panel/backup run — 129 passed; poster scheduling/integration follow-up — 51 passed; final orphan-focus panel run — 2 passed.
- `python3 scripts/check_renderer.py` — exit 0; 12 generated pooled/isolated pixel comparisons matched, diagnostics 0; 8 projects x 2 reloads passed. Four local-asset checks skipped. Evidence: `artifacts/renderer/adaptive-20261008-234144` (disposable).
- Regression coverage includes independent/shared display groups, malformed/ambiguous topology, desktop reorder, fullscreen entries without UUIDs, visit persistence, paused catch-up, rapid queued switches, Focus exit with unknown topology, old-schema migration and backup transient-state exclusion/rollback.
- Scoped poster tests cover current-Space-only writes, public-fallback exclusion, late request/encode rejection, mode changes, replacement gaps, current-only eject and all-Space restore. Native-video poster context is exercised through the real coordinator with a fake surface; Scene bindings carry context beside captured request generations.
- Offscreen WKWebView tests cover choice save, UUID-preserving reorder, current-desktop accessible name, unavailable mode/native validation, orphan removal and final-orphan focus. One Impeccable detector invocation returned `[]`; source-only reviewer disposition `ship` for its single corrected focus finding.
- Localization and JS syntax checks passed; 192 local documentation links resolved; diff check passed excluding generator-owned bindings. Upstream provenance updated, notices retained, CLAUDE.md remains a relative AGENTS.md symlink; no agent state staged.
- No desktop/window/screenshot, actual Mission Control/Space/Focus transitions, visible layout, VoiceOver, installed-app test, install/restart, commit or push. Inactive Spaces retain posters, not resident renderer instances; brief reload transitions and animated-lock-screen incompatibility are documented.

## 2026-10-08 — Multi-display wallpaper layouts, copy and swap

- Added saved per-display wallpaper arrangements, independent-display copy/swap, a searchable Shortcuts layout action, URL routing and backup merge support. Separate live per-Space assignments remain unimplemented.
- `python3 scripts/test.py` — exit 0; 268 Python tests passed; native 1,290 passed, 0 failed, 14 skipped of 1,304. Full gate ran once for this batch.
- Native evidence: `artifacts/tests/Tests-20261008-230934-164642.xcresult`, log `Tests-20261008-230934-164642.log` (disposable local evidence). Existing live Workshop/SteamCMD and native-media skips remain skipped.
- Targeted core/store/BridgeStore integration tests — 15 passed; panel/backup/integration/command/catalog run — 44 passed; final focus-boundary panel/store run — 7 passed. A test fixture return type was corrected before these successful runs.
- Checked complete preflight, copy/swap from original assignments, failure after mutation, restoring empty destinations, preserving unexpected external choices, cancellation cleanup, clean-editor admission, net history and newer queued user commands.
- Offscreen WKWebView tests cover save/rename/apply/delete, copy/swap and recovery errors, escaped names, missing-screen eligibility, Escape/focus return, English/Chinese/Japanese at 760 points and saving the 64th layout.
- Panel/native localization coverage and JavaScript syntax checks passed; 160 local documentation links resolved. Impeccable detector returned `[]` once on this batch's changed JS/CSS.
- Static review disposition `ship` for its single focus finding after correction and regression coverage. Rendered appearance and VoiceOver remain unverified; no additional visual inspection was authorized.
- `git diff --check -- . ':!App/Bridge/Generated'` passed; existing generator-owned output from the preview batch is excluded. CLAUDE.md remains a relative symlink to AGENTS.md; no agent state was staged.
- No renderer/bridge ABI changes in this batch, so prior renderer checks were not rerun. No desktop/windows/screenshots, real multi-monitor compositor/Spaces or Siri/Shortcuts run, Release rebuild, install, commit or push.

## 2026-10-08 — Advanced wallpaper automation and Focus restoration

- Added per-display weekday/time/sunrise/sunset and system-appearance choices, temporary Focus wallpaper/playlist overrides, and saved playlist/property preset Shortcuts and URLs.
- `python3 scripts/test.py` — exit 0; 268 Python tests passed; native 1,270 passed, 0 failed, 14 skipped of 1,284. Full gate ran once for this batch; no renderer code changed in this batch.
- Full native evidence: `artifacts/tests/Tests-20261008-194956-595159.xcresult`; log `Tests-20261008-194956-595159.log` (disposable local evidence).
- Targeted automation/planner/store/Focus/panel/command/catalog tests — 35 passed. Offscreen automation editor and backup tests — 33 passed after correcting a test-fixture initializer argument order.
- Covered DST and solar boundaries, persisted/manual precedence, Focus restoration and interrupted state, deleted saved plans, queued multi-field playlist edits, backup merge and rollback.
- Offscreen WKWebView flows cover save/edit/cancel/delete, hidden invalid timing fields, local weekday errors/focus, appearance clearing, solar location save/clear and compact overflow.
- Panel localization checks passed for English source plus Simplified Chinese, Traditional Chinese and Japanese; JavaScript syntax checks passed; 168 local documentation links resolved.
- Impeccable detector returned `[]` on the three changed automation/settings UI sources. Static reviewer disposition `ship` for the three listed fixes, all resolved; rendered appearance and VoiceOver remain unchecked.
- `git diff --check -- . ':!App/Bridge/Generated'` passed; generator-owned bindings from the preceding preview batch retain generator whitespace. `CLAUDE.md` remains a relative symlink to `AGENTS.md`.
- No live Focus/appearance transitions, Siri/Shortcuts, desktop interaction, screenshots, permission prompts, Release rebuild, installation, commit or push. Existing corpus/runtime skips remain skipped, not passing asset evidence.

## 2026-10-08 — Independent live wallpaper preview

- Added an explicit preview window for installed Scene, Video and Web wallpapers. Read-only draft export, independent playback, mute by default, reload, scoped pointer input and close/replacement cleanup leave desktop assignments and history unchanged.
- python3 scripts/build.py --renderer-only: exit 0; regenerated UniFFI bindings for wallpaper_preview. project.yml and XcodeGen include the existing renderer C header for the app and hosted tests; no vendored C++ behavior changed.
- python3 scripts/test.py: final exit 0; all 268 Python tests passed; native tests 1242 passed, 0 failed, 14 skipped of 1256. An earlier gate stopped at CodeSign because com.apple.FinderInfo returned on disposable Debug output; only that attribute was removed before rerunning.
- The 14 native skips remain opt-in real-media, live Steam installation and live Workshop network cases. Preview regressions use isolated fixtures/offscreen views and cover drafts, path bounds, storage isolation, mute, cancellation, generation fences, readiness timeout, pointer mapping and the inspector action.
- WallpaperPreviewLayoutTests checks the 480-point NSView content in English, Chinese and Japanese without an NSWindow; controls fit and errors retain a full-width selectable row and complete tooltip. Scoped static UI review findings were resolved; the WebUI mechanical detector returned no findings.
- python3 scripts/check_rust.py: exit 0 for core, bridge, core-integration and shader groups. Six desktop/corpus cases were explicitly excluded and three asset-dependent shader checks reported skips; those surfaces remain unverified.
- python3 scripts/check_renderer.py: exit 0 with GPU and realtime checks enabled. All 12 generated pooled/isolated pixel pairs matched with no diagnostics; 8 projects completed two reload cycles. Four local-asset cases were skipped (2 text, 1 video, 1 native-Metal local-project case).
- Localization checks and local documentation link checks passed. git diff --check passed excluding raw generator-owned UniFFI output, whose existing generator emits trailing whitespace; bindings were not edited manually.
- Actual preview-window presentation, Scene/Video swapchain first frames in that window, OS visibility transitions and VoiceOver were not exercised. Web FPS is a cooperative host-property request; preview audio response and media integration are unavailable. No Release app, installation or desktop run was requested or delivered.
