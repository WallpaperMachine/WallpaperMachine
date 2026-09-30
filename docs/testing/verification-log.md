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

## 2026-09-30 — Changelog defaults to the app language

- python3 scripts/test.py --only WhatsNewTests — exit 0; 10 passed, 0 failed, 0 skipped; covers saved language precedence and System matching.
- Offscreen native smoke — exit 0; en and ja initially show English, zh-Hans and zh-Hant show Simplified Chinese; manual switching remains reversible. Temporary harness removed.
- python3 scripts/test.py — exit 0; 852 passed, 0 failed, 11 skipped of 863.
- No new desktop capture or Release rebuild; running app unchanged.

## 2026-09-30 — Readable changelog window with language tabs

- Offscreen native AppKit smoke with bundled release history — exit 0; English → 简体中文 → English at 760 × 720 and 600 × 480 points; first note visible, wrapping and scrolling exercised, scrolled switches reveal the first version, suppression persists. Temporary harness removed.
- python3 scripts/test.py --only WhatsNewTests — exit 0; 9 passed, 0 failed, 0 skipped.
- python3 scripts/test.py — exit 0; 851 passed, 0 failed, 11 skipped of 862.
- Desktop appearance and actual Window Server presentation unverified; no windows opened. No Release rebuild requested or performed.

## 2026-09-30 — First downloaded wallpaper support prompt

- Added a persistent, once-only support offer after a successfully installed Workshop/pixiv wallpaper receives a successful explicit activation; failed applies, automatic rotation, restoration and local imports do not qualify.
- Initial targeted state/activation/panel run: 18 passed, 6 panel failures because windowless WebKit reports document.hidden. The offscreen fixture now simulates page visibility independently from native presentation, matching the existing Discover tests.
- python3 scripts/test.py --only WebPanelSupportPromptTests: exit 0; 7 passed, 0 failed, 0 skipped. Covers actual display acknowledgment, persistence/reload, welcome/modal/hidden deferral, captured Star and localized Pricing URLs, link failure retry, Escape and body-focus restoration.
- python3 scripts/test.py: exit 0; 226 Python tests passed; 861 native tests: 850 passed, 0 failed, 11 skipped. The full gate ran once after the targeted fix.
- Skipped opt-in tests: 9 NativeVideoPlayerMediaTests requiring real media decoding and 2 live Steam Workshop queries. Renderer probes were not run; no renderer or generated binding changes.
- Changed JavaScript syntax checks, native localization JSON parsing and git diff --check passed. English and Chinese Pricing destinations each returned HTTP 200. XcodeGen regenerated the project for the new Swift files.
- Visual presentation and real desktop/VoiceOver behavior remain unverified; no windows, screenshots, wallpaper changes or external browser launches. No Release build, install, commit or push requested.

## 2026-09-30 — Release notes read squash merges per listed commit; CI serial cost corrected

- Change: scripts/release_notes.py model_prompt splits a squash merge's body at its '* type(scope): subject' lines; each listed commit gets its own 1,500-character cut, internal ones only their subject line; Co-authored-by/Signed-off-by/Reviewed-by/Claude-Session trailers and GitHub's --- rule are dropped. Budget unchanged (120,000).
- Why: 1.2.0's generated notes missed Workshop updates, automation, Workshop sources, the What's New window and the black wake placeholder, all past the first 1,500 characters of #15 and #16.
- New test ModelRangeTests.test_a_squash_merge_brings_the_body_of_every_commit_it_lists fails on the old code (later commits missing) and passes now; test_release_notes.py 56/56.
- Preview of the real v1.1.0..7d3afcf range (no model request): 12,804-character prompt, every #15/#16 feature body present, no trailers, nothing cut.
- build.yml Test comment and docs/testing/README.md now say serial costs the CI runner almost nothing (300 s against 278 s parallel for the 1.2.0 gate), not four times as long.
- Gate: python3 scripts/test.py - 828 passed, 0 failed, 11 skipped of 839. No --ai run against the gateway; no Release build (none needed for scripts/CI/docs).

## 2026-09-30 — PR 16 Claude review: topology state and bundled history

- Standalone Swift smoke compiled the production lock-screen service, selection journal, asset publisher and manifest against isolated host seams and a disposable wallpaper-store fixture. No windows or real wallpaper-service reloads.
- Before/after: unchanged topology retained the manifest in both; replacement pending readiness changed from isEnabled=false to true; a compatibility error followed by missing UUID changed from erased error/restarted monitor to preserved error/stopped monitor. Actual failure still cleared the manifest.
- Release publisher smoke: bilingual Unreleased and internal H2 headings were accepted before and rejected after. The real release_notes.py --tag 1.1.0 --to HEAD --release-body command exported bilingual notes without changing CHANGELOG.md.
- python3 scripts/test.py --only LockScreenWallpaperServiceTests --only WhatsNewTests: 25 passed after correcting the compatibility fixture to change the published inputs; initial targeted run was 24 passed / 1 fixture failure.
- python3 scripts/test.py: exit 0; Python modules passed (55 release-note tests), native 828 passed / 0 failed / 11 skipped.
- Opt-in media-device and live-network cases skipped. No renderer code or bridge API changed; check_renderer.py not rerun.
- Documented nonopaque-layer compositor cost as unmeasured, retained-frame resize/failure behavior, and missing-notes retry. Physical lid-close/wake, host acquire-error behavior and What's New presentation remain unverified.
- No Release app rebuild, installation or restart; the running app retains its previous behavior.

## 2026-09-29 — Eye-friendly fallback during display wake

- Offscreen production-layer smoke reproduced RGBA [255,255,255,255] before the fix and [0,0,0,255] after it for initial, resized and recreated surfaces; no window or drawable was created. Retained as wallpaper_background.
- cargo test --release -p wallpaper-core --test wallpaper_background: exit 0; all three opaque-black pixel scenarios passed.
- cargo test --release -p wallpaper-core --lib: exit 0; harness reported 222 passed. Opt-in AppKit window tests returned without running; not desktop evidence.
- python3 scripts/test.py: exit 0; Python modules passed, native 824 passed / 0 failed / 11 skipped (9 media-device and 2 live-network cases).
- python3 scripts/check_renderer.py: exit 0; ten synthetic pooled/isolated pixel comparisons matched with zero diagnostics; eight projects reloaded twice.
- Physical external-display lid-close/wake timing remains unverified. Black replaces the app-owned white fallback; no guarantee is made about macOS-owned transitions.
- No Release app rebuild, installation, desktop control or app restart; the running app retains its old behavior.

## 2026-09-29 — Merge origin/main and build Release

- Merged origin/main 98e90a8 with six local commits; retained What's New and Dock/Finder import startup, adopted persistent import ownership, regenerated Xcode project and preserved both verification histories.
- Completed Japanese and Traditional Chinese translations for five What's New strings exposed by the merged localization gate.
- Removed obsolete sidebar checkbox-count and default-list assertions; retained interaction, layout and persistence coverage. Targeted ControlPanelLibraryTests: 9 passed.
- python3 scripts/test.py: all 17 Python suites passed; native 824 passed, 0 failed, 11 skipped of 835. Earlier attempts exposed missing translations and stale sidebar assertions, corrected before the passing gate.
- python3 scripts/build.py --swift-only --configuration Release: passed; existing renderer and bindings reused, no incoming renderer changes.
- codesign --verify --deep --strict: passed. diff -qr WebUI versus Release bundled WebUI and cmp bundled CHANGELOG.md: byte-identical.
- No app launch, restart, installation or desktop visual verification; opt-in native-media and live Workshop checks remain skipped.

## 2026-09-29 — Bilingual What's New Release build

- python3 scripts/test.py via a temporary same-user Aqua launch job: exit 0; all 17 Python suites passed, including 51 release-note tests; native 746 passed, 0 failed, 11 skipped of 757. The previous lock-screen recovery blocker now passes.
- python3 scripts/build.py --swift-only --configuration Release: exit 0; built WallpaperMachine.app, version 1.1.0, using the existing renderer and bindings. No version bump requested.
- codesign --verify --deep --strict on the Release bundle: exit 0.
- cmp of source and Release-bundled CHANGELOG.md: exit 0; bilingual history is byte-identical. diff -qr of WebUI and bundled Contents/Resources/WebUI: exit 0.
- Skipped: 9 opt-in native-media and 2 live Workshop cases; no desktop visual check, live release-note model call, install, launch or restart. Temporary Aqua launch job and helper removed.

## 2026-09-29 — Retain wallpaper presentation across wake topology changes

- Hidden-window Rust smoke: before the fix, three origin/primary/refresh updates performed 3 drawable-size writes and 3 forced AppKit redraws; afterward both counts were 0 with the same layer, and a real resize still produced a 256x144 window/drawable at scale 1. Window ordering was suppressed; no wallpaper or visible desktop window was changed. Temporary smoke removed.
- LockScreenWallpaperServiceTests/testWakeDisplayLookupGapPreservesCommittedWallpapersAndRecovers failed before the Swift fix and passed afterward; partial/all-display lookup gaps preserve manifest, native selection, provider ownership and the status monitor, then settled disconnect and last-wallpaper removal still reconcile.
- python3 scripts/test.py --only LockScreenWallpaperServiceTests: exit 0, 14 passed, 0 failed, 0 skipped.
- python3 scripts/test.py: exit 0; all 17 Python modules passed; native 746 passed, 0 failed, 11 skipped (9 opt-in media and 2 live Steam cases).
- The initial targeted launch in Background exited 250 with IDELaunchServicesLauncher childPID > 0; the failing-before, passing-after and full native runs used a temporary same-user Aqua launch job. Jobs and temporary runners removed.
- cargo test --release -p wallpaper-core --lib with the build.py cargo environment: exit 0; runner reported 222 passed. Opt-in desktop/private-asset cases were not enabled; this is not physical wake proof.
- python3 scripts/check_renderer.py: exit 0; generated ten-scene pooled/isolated pixel comparisons matched, no diagnostics, and 8 projects x2 reload cycles passed. No user wallpaper corpus was requested.
- Real external-primary lid/sleep/wake visual timing remains unverified. No Release app build, launch, install, desktop automation or screen capture; the running app still has its previous behavior.

## 2026-09-29 — Bilingual post-update What's New

- Implemented native post-update window, persisted opt-out and version-range history; all 18 historical releases now contain English and Simplified Chinese.
- Isolated swiftc smoke: actual native content laid out offscreen at 560×400; 1.0.2 → 1.1.0 includes both releases and their complete translations; checkbox persistence and Close callback passed. No windows opened.
- python3 scripts/test.py --only WhatsNewTests: initial Background-session launcher failed with exit 250 before tests; same command through a temporary same-user Aqua launch job passed 7/7, exit 0.
- python3 scripts/test.py through the Aqua job: 17 Python suites passed, including 51 release-note tests; native result 745 passed, 1 failed, 11 skipped of 757, exit 65.
- Shared-workspace blocker: LockScreenWallpaperServiceTests.testWakeDisplayLookupGapPreservesCommittedWallpapersAndRecovers failed while preserving enabled state and committed topology. This concurrently added test is absent from HEAD; its test and service edits were not changed by this task. Commit withheld because the full gate did not pass.
- python3 scripts/release_notes.py --tag v1.1.0 --release-body --output <temporary-file>: exit 0; actual output matches the recorded current notes exactly, and all bundled historical sections passed bilingual publication validation.
- History comparison: all 18 version/date headings, English notes and compare links preserved; translated bullet counts match. cmp confirmed Debug-bundled CHANGELOG.md is byte-identical to the source.
- Skipped: 9 opt-in native-media and 2 live Workshop tests. No live release-note model call, desktop visual check, Release build, install or app restart performed. Temporary Aqua job removed.
