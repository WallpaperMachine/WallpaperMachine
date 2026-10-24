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

Retention: this file keeps the ten newest entries. Add an entry with
`python3 scripts/log_verification.py --title "…" --line "…"`, which prepends it
and moves whatever falls past ten verbatim into a monthly file under
[archive/](archive/); promote anything durable before it goes. Editing an
entry's recorded result is not allowed.

## 2026-10-24 — What's New: Release build with the bundled changelog

- Same code as the entry below (ce5402dc), built after its test run.
- python3 scripts/build.py --swift-only --configuration Release: exit 0; built WallpaperMachine.app 1.6.2.
- Bundled CHANGELOG.md matches the repository's and parses with AppReleaseHistory: 39 releases, 1.6.2 notes in English, 简体中文 and 한국어.
- New window and Settings strings present in all five shipped .lproj catalogs of the built app.
- Not checked: the windows on screen; the app was not launched by the agent.

## 2026-10-24 — What's New: Don't Show Again and release history

- Post-update window: Don't Show Again button (sets the opt-out and closes) replaces the checkbox; Show/Hide Earlier Releases adds older bundled releases.
- Settings › About: Show What's New after updates switch (undoes the opt-out, cleared by Reset all settings) and Release history › Show.
- Release history opens the same window with every bundled release up to this version and records nothing.
- python3 scripts/test.py --only WhatsNewTests/AboutSettingsTests/PanelSettingsResetTests/SettingsEditingModelTests/ClientPreferencesTests: exit 0; 49 passed, 0 failed, 0 skipped.
- python3 scripts/test.py: exit 0; 4114 passed, 0 failed, 47 skipped.
- Not checked: the windows on screen (layout, scrolling to earlier releases); no Release build, no desktop run.

## 2026-10-24 — Keep each visited desktop's wallpaper loaded and paused

Follow-up to PR #77: a display with a different wallpaper for each desktop keeps the wallpapers of visited desktops parked (renderer, bridge, web and video hosts) instead of reloading them on every desktop change; memory pressure and Stop (free memory) let them go.

- `python3 scripts/check_rust.py` — exit 0; core, bridge, core-integration and shader all pass, including the new `engine::actor::space_parking_tests` (9), `tests::space_parking` (3) and `first_frame_tests::a_wallpaper_the_display_keeps_parked_is_not_awaited`
- `python3 scripts/check_renderer.py` — exit 0; corpus and media cases skipped as listed (no local assets)
- `python3 scripts/test.py` — exit 0; 4107 tests: 4060 passed, 47 skipped, after one rerun: the first run on the final code failed `EnergyUsageMonitorTests/testKernelCountersForThisProcessAdvanceWithGPUWork` (3.7 mW against a 10 mW floor, right after the renderer check), which passed alone and in the rerun
- New Swift tests: `WallpaperSpaceParkingTests`, per-window placement and opening windows in `WallpaperSpacePinningTests`, kept clips and pages in `NativeVideoWallpaperHostTests` and `WebWallpaperHostLifecycleTests`, the auditor's kept-window excuse, pressure edges in `MemoryPressureMonitorTests`
- Not checked: no desktop run (no intro on return, the kept frame during a swipe, a shared wallpaper on several desktops, `CGSAddWindowsToSpaces`/`CGSRemoveWindowsFromSpaces`, the memory held, release under real memory pressure); the Release app was not rebuilt

## 2026-10-23 — Different wallpaper for each desktop: windows kept on their desktop, saved posters, new panel UI

Space mode reworked: wallpaper windows of a display in the mode stay on its current desktop and move hidden on a desktop change; other desktops get their wallpaper's saved poster; Apply sets the current desktop's wallpaper; the switch moved onto the display card and the toolbar menu with a desktop strip and a searchable chooser.

- `python3 scripts/test.py` — first run 1 failure (SettingsSectionsLocalizationTests: "Mission Control"/"Spaces" keywords untranslated), fixed; rerun exit 0: 4083 tests, 4037 passed, 46 skipped
- `python3 scripts/build.py --swift-only --configuration Release` — OK (ad-hoc signed)
- Authorized desktop run, macOS 27.0.1, one display, three desktops: a standalone window probe showed CGSMoveWindowsToManagedSpace moves an own window to the current Space; re-ordering, toggling canJoinAllSpaces and moveToActiveSpace do not; an alpha-0 window stays occlusion-visible and keeps vending drawables
- Live app: Mission Control showed desktop 2 Windows 11 and desktop 3 Plastic Beach (before: every desktop showed the live window); swipes show the destination's poster; warm loads shown 0.4 s (Plastic Beach) and 0.9–1.0 s (Windows 11) after the swipe ends
- Relaunch without visiting: both other desktops and the current one got their own poster within ~3 s
- Panel: card switch, desktop strip, chooser popover and the toolbar's toggle and "· Desktop 1" label rendered as intended
- Gap: ad-hoc test builds ask again for System Audio Recording; an audio-responsive scene's first frame waits for the answer (6.4 s and 180 s stalls seen); a pixiv keychain prompt was denied
- Not checked live: Apply assigning the current desktop (unit-tested), chooser search typing, multiple displays with separate Spaces, web/video on a pinned display, VoiceOver

## 2026-10-24 — Daily active count (DAU/MAU) without an install id

- App: TelemetryActiveCount sends one ping per UTC day to /api/telemetry/active (random per-day ping id, day, version, source, monthFirst); hourly retry with the same ping, next send 0-15 min after UTC midnight; no count with WALLPAPER_MACHINE_HOME or a defaults suite.
- python3 scripts/test.py --only TelemetryActiveCountTests --only TelemetryClientTests --only TelemetryServiceTests: 18 passed, 0 failed.
- python3 scripts/test.py (full gate, worktree): Python script tests OK; native 4062 passed, 0 failed, 47 skipped; 1 runtime warning (main-thread call), not traced to this change and not baselined.
- Website (separate repo, branch feat/telemetry-active-count): npm run typecheck OK; local wrangler dev on a scratch D1 with migration 0002: retries (same and lowercase ping) counted once, a day-behind clock kept its day, a far-off clock took the arrival day, bad schema/ping/day/agent 400, cron prune kept 400-day totals and 2-day pings.
- Dashboard DAU/MAU SQL run on the scratch D1 gave the expected sums; the page's new section was not viewed in a browser (owner sign-in needed).
- Not done: no D1 remote migration, no Worker deploy, no app Release build, no desktop run.

## 2026-10-24 — Library location: move library and downloads to an external drive

- python3 scripts/test.py: passed (Python stage OK; native 4051 passed, 0 failed, 47 skipped).
- New: StorageMoveServiceTests, StorageCopierTests, StorageLocationTests, DownloaderStorageTests, WallpaperBackupTests moved-library round trip, PanelStorageActionsTests move actions.
- Another disk is simulated with a fake StorageVolumeInspecting; no real external drive, ExFAT disk or eject was exercised.
- Not checked: Settings › Storage rows and the Wallpaper Library Unavailable window visually, the removable-volume privacy prompt, a live Steam download to a moved library.
- Renderer built in this worktree with scripts/build.py --renderer-only; bindings unchanged. App not rebuilt as Release.

## 2026-10-24 — Desktop posters kept until the wallpaper changes (issue 79)

macOS 26+ WallpaperAgent keeps a full-size bitmap of every desktop picture file and never deletes it; animated wallpapers made every poster retake a new file. Snapshots that change no display, Space changes, wakes and resumes now keep a settled poster, and a frame nobody asked for never replaces one.

- `python3 scripts/test.py --only DesktopWallpaperTests` — 77 passed; the new hours-of-activity test failed (13 captures instead of 3) with the old two-minute expiry put back temporarily
- `python3 scripts/test.py` — exit 0; 4070 tests: 4023 passed, 47 opt-in skipped; Python script tests passed; 1 runtime warning (main-thread call) from another class, not raised by DesktopWallpaperTests
- Not verified: WallpaperAgent's cache on a real Mac (another app's container, not read), real Mission Control thumbnails, `AppDelegate.desktopPosterLayout` (wiring, no unit test); app not rebuilt
- Space-selection mode still takes posters on every Space visit that switches the wallpaper; not changed here

## 2026-10-23 — Report on GitHub opens the bug form with required fields

- bug_report.yml: What you did, What went wrong, What you expected and the diagnostics report are required; app facts go to optional wallpaper, version and app-details fields.
- ExternalLink.newIssue opens ?template=bug_report.yml and prefills only those three field ids; no required field is filled by the app.
- YAML parsed with PyYAML; the app's query names match the form's field ids (grep both sides).
- python3 scripts/test.py --only ExternalLinkTests --only PanelLibraryStateTests: 20 passed; --only InspectorPolicyTests: 19 passed.
- python3 scripts/test.py: 4016 passed, 0 failed, 46 skipped (after rebuilding the stale renderer library with build.py --renderer-only).
- Not checked: GitHub's rendering of the form and the URL prefill; it only takes effect once the template is on the default branch.
- Blank issues stay on for the body-prefilled link of app versions up to 1.6.0; app not rebuilt.

## 2026-10-23 — Web wallpapers: assigning the property listener is not a delivery

A React page that assigns `wallpaperPropertyListener` while it renders (issue #69) looped on the host script's synchronous replay until React error 301 left it blank. The host script now replays only what the page has not taken in, once after the assigning turn, and once more for a listener a handler assigns during that replay. This Mac cannot link the test host, so the native gate runs in CI on the pull request (#72), as agreed on the issue.

- Offscreen `WKWebView` probe with the app's user scripts (no window, no audio) on the reported page: old script → React error 301, 52 listener assignments, empty `#root`; fixed script → full UI, 3 assignments, the player calls `play()`
- Probe scenarios, old vs fixed: render-time assignment (25+ deliveries and an error vs each value once, one pass per render), replaced listener (whole set vs only changes), late listener with pause (called during the assignment vs once after it), directory replay (resent vs only what is owed), throw-and-reassign (stack overflow vs one call); a handler gained later and a throwing first handler behave as before
- Review follow-up, the host script run in Node, PR head 5293a5af vs fix: a listener assigned during the replay (general properties never delivered vs once), a restaged file that arrives with no handler (lost vs owed to the next listener); throw-and-reassign still one call, partial take-in plus throw-and-reassign one extra pass; synchronous re-render, replaced and late listener unchanged
- `swiftc -typecheck` of the shared web wallpaper sources — exit 0; `swiftc -parse` of the two changed test files — exit 0
- `Tests/Unit/WebWallpaper/` (`WebWallpaperAuthorAPITests`, `WebWallpaperSuspensionTests`) updated and extended; not compiled or run locally
- Native stage of `python3 scripts/test.py` — not run: no Rust or renderer Homebrew packages here, so the test host does not link; left to CI on the pull request. Python script tests not rerun after rebasing onto f2d6862e (no Python change)
- Not compared with Wallpaper Engine's frame (VM not used); not checked on the desktop; no Release build

## 2026-10-21 — Opt-in compiler uniform-layout diagnostics

- python3 scripts/check_rust.py --observer-uniform-layout: ordinary and diagnostic stages passed; normal shader990 and observer shader1001 reported tests,9core exclusions and guarded shader skips retained.
- Actual C callers compiled and ran once per mode from the same owned synthetic request: ordinary reflection, annotation metadata, MSL and stage payloads matched; identities/cache keys differed; physical Boolean, widened matrix and padded-array metadata survived the existing accessor.
- The C smoke restored the ordinary static archive afterward. This observes compiler-origin metadata, not native Metal layout, active variants, bound buffers, draws or image parity.
- Final composed python3 scripts/check_rust.py:2267reported passes (388core/872bridge/17integration/990shader),9core exclusions.
- python3 scripts/build.py --renderer-only: passed with generated bindings preserved; python3 scripts/check_renderer.py: passed,12generated pairs/reload coverage,17asset/corpus skips.
- python3 scripts/test.py:425Python and3930native passed;46native skips. No permission, hardware-audio, desktop, private-corpus or network opt-in.
- Retired57assertion-mapped inherited cases while retaining contributor/Henry islands. Earlier failed consumer source/logs and corrected fixture/contract assumptions remain preserved; no failure was relabeled.
- No Release app build or launch; licensing/rights clearance, current-main reconciliation and native effects acceptance remain separate.
