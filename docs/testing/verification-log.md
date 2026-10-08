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

## 2026-10-05 — Code audit fixes: downloads, playlists, Discover, lock screen, updater, panel

- Scope: 16 fixes and Open on Steam from a read-only audit of aa47389 (Swift app, WebUI, bridge to panel); no renderer change.
- python3 scripts/test.py: Python suites OK; native 1186 passed, 0 failed, 14 skipped of 1200 (opt-in media and network tests).
- New tests that failed before their fix: silent Workshop transfer outliving the timeouts (mutation-checked), lock-screen refresh during readiness wait, failed resume across display reconnect.
- Also covered: failed source switch clears Discover and pixiv, requested playlist skip while paused, allowlisted panel links, queued panel request after a failure, screened subscriptions empty state, collections read-limit count, update digest required, newest poster per display, Steam cookie redirect stripping, paused web audio demand.
- Web navigation: refused top-frame navigation, replaced loads and hash routing never fail the page even without filtering; the suspected -999 report was not reproducible, so no code change.
- Not unit-testable, not run on a desktop: per-display uncover re-evaluating playlists, error alerts from the main run loop, poster sync in screen-saver-only mode, Open after a failed start.
- Not done: update code-signature pinning (self-signed release certificate, planned Developer ID move); setenv race in BridgeStore not reproducible.
- No Release build, no desktop, Steam sign-in or lock-screen run.

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
