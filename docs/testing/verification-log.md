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

## 2026-10-08 — Wallpaper history, playlist ordering and failure recovery

- python3 scripts/test.py: exit 0; all 268 Python tests passed; native tests 1227 passed, 0 failed, 14 skipped of 1241. The full gate ran once after integration.
- The 14 native skips were 11 opt-in NativeVideoPlayerMediaTests and 3 live Steam/Workshop network or installation tests; no real media or live-account coverage is claimed.
- Targeted final run of ControlPanelPlaybackToolsTests and WallpaperActivationRecoveryTests: 21 passed, 0 failed, 0 skipped. Offscreen WebKit covered repeated keyboard moves, boundary focus fallback, drag sorting, stale-drag rejection, history order, escaped titles, current-state accessibility and target-only clearing.
- History and playlist regressions cover persistence, bounded recent lists, repeated Previous, failed-apply preservation, exact reorder membership, cooldown expiry, cancellation, bounded fallback attempts and a newer manual command taking precedence.
- python3 -m unittest scripts.tests.test_panel_localization: 5 passed. node --check succeeded for panel.js, settings.js and playlist-order.js. The Impeccable mechanical detector returned no findings for the changed WebUI targets; the scoped source review findings were resolved.
- XcodeGen regenerated the project for WallpaperHistoryStore and its new test files. Local documentation link targets and git diff --check passed.
- The first targeted build was blocked by com.apple.FinderInfo on disposable Debug products. Only that attribute was removed from build/Build/Products/Debug before the successful test runs.
- Desktop playback, OS shortcut invocation, actual dragging in an on-screen window and VoiceOver were not exercised. Failure skipping handles errors returned by Apply; it does not diagnose a visual defect after a successful assignment.
- No Release build, installation, app launch/restart, commit or push was requested or performed.

## 2026-10-07 — Keep web wallpaper animation running through transient occlusion

- Desktop web pages now leave window occlusion to WallpaperPresentationPolicy through a guarded per-view WebKit selector; host detach and inactive suspension remain in place.
- Before the fix, the new offscreen transient-occlusion regression failed because animation frames stopped while the host still allowed playback.
- python3 scripts/test.py --only WebWallpaperSuspensionTests: 5 passed, 0 failed, 0 skipped after the fix.
- python3 scripts/test.py: 268 Python tests passed; 1211 native tests passed, 0 failed, 14 skipped of 1225. Full gate run once.
- Skipped: 11 native media/device cases, 2 live Workshop searches, and 1 live SteamCMD install; opt-in layers were not enabled.
- The first targeted build hit the documented Finder metadata signing failure; clearing xattrs from Debug products let the unchanged command run.
- The regression uses an unshown window with simulated occlusion. Real Show Desktop/Space animations and the original wallpaper were not exercised on the desktop.
- No renderer changes, Release build, app installation/restart, settings mutation, commit, or push.

## 2026-10-07 — Automatic recovery from duplicate wallpaper extensions

- Activation now validates and reconciles native extension registrations to the running app, preserving other app bundles and verifying the resulting registry.
- A wrong extension copy triggers one fresh activation; snapshot refreshes share registration work and preserve the recovery limit, while disabling or shutdown cancels preparation.
- Read-only pluginkit discovery confirmed installed and worktree Debug registrations before implementation; no live registration-repair command was executed.
- Targeted iteration: python3 scripts/test.py --only LockScreenExtensionRegistrationTests --only LockScreenWallpaperServiceTests --only LockScreenExtensionDiagnosticsTests passed 60 tests; the final gate also covers parent-unregistration removing its extension first (61 related tests passed).
- Full gate, run once: python3 scripts/test.py exited 0; 268 Python script tests passed; native tests: 1209 passed, 0 failed, 14 skipped of 1223.
- Skipped opt-in coverage: 11 NativeVideoPlayerMediaTests and 3 live Steam network/install tests; no private asset corpus or desktop checks were run.
- Initial targeted compilation hit the documented Finder/File Provider xattr signing issue; cleared disposable Debug product xattrs with xattr -cr build/Build/Products/Debug, then verified through the passing gate.
- git diff --check passed; owning documentation links resolve; all shipped native language catalogs contain the new messages.
- Unverified: real LaunchServices/PlugInKit repair convergence, macOS choosing the intended extension, and visible lock-screen/screen-saver transitions. No Release build, app installation/restart, or desktop automation.
