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

## 2026-09-30 — Storage layout spacing

- Offscreen Chrome smoke: long paths in English, Japanese, Simplified and Traditional Chinese; no content overflow at wide, minimum-window and narrow-container sizes; 12px path-to-note and 16px note-to-actions spacing.
- Offscreen interaction smoke: keyboard disclosure toggle, disclosure preservation across snapshots, empty-cache/history disabled states, pending-action disabling and error recovery passed using synthetic state; no native storage operations invoked.
- Impeccable detector: WebUI/settings.js and WebUI/settings.css returned no findings.
- python3 scripts/test.py: 851 passed, 1 failed, 11 skipped; hidden-panel sync test hit WebKit InvalidTransition teardown error.
- python3 scripts/test.py --serial: passed, 852 passed, 0 failed, 11 skipped.
- Live app visual presentation and desktop interaction unverified; no screenshots captured or Release app rebuilt.

## 2026-09-30 — Clarify generic Workshop download failures

- Temporary PTY smoke: python3 scripts/test.py --only DownloadFailureCopySmoke passed (1 test); all three generic failure forms emitted purchase/account recovery guidance without offering authentication retry. Temporary smoke removed afterward.
- python3 scripts/test.py passed: 852 native tests passed, 0 failed, 11 skipped; all 17 Python test modules passed.
- Skipped: 9 opt-in native video media cases and 2 live Steam Workshop cases.
- Updated English, Japanese, Simplified Chinese, and Traditional Chinese native error catalogs and the Workshop download documentation.
- Live non-owning Steam account and visual error layout not exercised. No Release rebuild or desktop interaction.

## 2026-09-30 — Advanced performance settings refinement

- Local WebUI preview: captured matching before/after views with illustrative wallpaper reports; exercised both renderer selectors and all five switches, keyboard disclosure controls, snapshot focus/open-state preservation, pending/rejection recovery, empty/shared-decode/fallback reports, and escaped long titles.
- Local WebUI preview: no overflow in 24 combinations of 760/960/1240 px, light/dark, and en/ja/zh-Hans/zh-Hant; sampled Advanced text contrast exceeded 4.5:1 in both themes.
- Impeccable detect over WebUI/settings.js and WebUI/settings.css — exit 0, no findings.
- python3 scripts/test.py — exit 65; 851 passed, 1 failed, 11 skipped. ControlPanelSyncTests.testHiddenPanelContinuesSetupAndObservesNestedDownloadChanges hit InvalidTransition during WebKit teardown.
- python3 scripts/test.py --serial — exit 0; 852 passed, 0 failed, 11 skipped of 863; Python script suites also passed. Skips: 9 opt-in media/device cases and 2 live Steam cases.
- Desktop app presentation not checked; preview uses the real settings renderer and CSS with an isolated fixture. No wallpaper changes, app restart, or Release rebuild. Temporary preview files and servers removed; requested comparison images remain disposable.

## 2026-09-30 — English-only GitHub release notes

- python3 -m unittest discover -s scripts/tests -p test_release_notes.py — exit 0; 56 passed; bilingual history remains required and GitHub keeps only English plus the compare link.
- Actual release_notes.py --tag v1.2.0 --release-body CLI — exit 0; English matches the published English section; Chinese omitted; compare link, download footer and build SHA preserved.
- python3 scripts/test.py --serial — exit 0; 852 passed, 0 failed, 11 opt-in skips of 863.
- gh release edit v1.2.0 --repo WallpaperMachine/WallpaperMachine --notes-file … — exit 0; live readback confirms English-only notes, no raw commit appendix, and unchanged assets, tag, title, publish date and release flags. Description reduced from 8,192 to 3,740 bytes.
- The app’s bundled changelog remains bilingual. No app rebuild, install, or desktop test. Temporary previews removed.

## 2026-09-30 — Remove raw commit messages from GitHub release pages

- python3 -m unittest discover -s scripts/tests -p test_release_notes.py — exit 0; 56 passed.
- Actual release_notes.py --tag v1.2.0 --release-body CLI before/after — exit 0; 8,079 → 6,433 bytes; bilingual notes and install/checksum footer unchanged, only raw commit appendix removed. Temporary previews removed; published release not edited.
- python3 scripts/test.py — exit 65; 851 passed, 1 failed, 11 skipped; ControlPanelSyncTests.testHiddenPanelContinuesSetupAndObservesNestedDownloadChanges hit the documented WebKit InvalidTransition error.
- python3 scripts/test.py --serial — exit 0; 852 passed, 0 failed, 11 skipped of 863.
- No app-code change, Release rebuild, desktop test, or remote publication.

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
