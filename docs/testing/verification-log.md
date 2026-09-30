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

## 2026-09-30 — Energy readout hierarchy and measurement disclosure

- python3 scripts/test.py — exit 0; Python suites passed; native 853 passed, 0 failed, 11 skipped (9 opt-in media, 2 live Workshop). The shared tree includes unrelated concurrent window-sizing changes.
- Headless Chromium on the real WebUI: 249 state/theme/language/layout cases passed at 1100px and the native 760px minimum, plus an isolated 360px settings container; no energy-card overflow. Tested text contrast stayed at least 5.33:1 across light/dark and neutral/warm/cool tones.
- Space/Enter disclosure operation passed; open state and focus survived energy pushes and snapshots, and updates preserved focus on the quality slider. Measuring, unavailable, GPU contention, battery omission, watt units, zero values and before/after comparisons exercised.
- Impeccable mechanical detector on settings.js and settings.css — exit 0, no findings.
- No screenshots, desktop interaction or native visual review; power sampling behavior unchanged. No Release rebuild or app restart.

## 2026-09-30 — Control-panel full-screen navigation (#17)

- python3 scripts/test.py --only ControlPanelWindowSizingTests: 2 passed, 0 failed, 0 skipped.
- Temporary offscreen AppKit smoke executable: opaque title-bar chrome intercepted navigation before the layout change; the fixed layout and restored windowed layout both delivered hits to content and preserved the window frame.
- Regression coverage exercises 1920×1080, 960×1080 and 760×560 bounds, unobscured content, navigation hit-testing and restoration of the unified title-bar layout.
- python3 scripts/test.py: all 17 Python test modules passed; native gate 853 passed, 0 failed, 11 skipped of 864.
- Skipped: 9 opt-in NativeVideoPlayerMediaTests and 2 live-network WorkshopTests; no asset-dependent skips.
- Live full-screen and Split View transitions and visual presentation remain unverified; no window was shown or Space transition requested.
- Release app not rebuilt; the running app remains unchanged. Unrelated concurrent WebUI and documentation edits were preserved.

## 2026-09-30 — Keep the active-display filter on one line

- Offscreen WKWebView smoke — exit 0; 24 cases across 760, 840, 841, 1040, 1041 and 1280px in English, Japanese, Simplified Chinese and Traditional Chinese. The full label occupies one line without overflow; checking and clearing Active filters the expected wallpapers. Discover widths and collapsed layout remain unchanged. Throwaway probe removed.
- `python3 scripts/test.py` — first pass failed: 850 passed, 2 failed, 11 skipped. The broad sidebar sizing rule changed Discover width; it is now scoped to the Active row. The other failure was the documented WebKit InvalidTransition/deinit error.
- `python3 scripts/test.py --serial` — exit 0; 852 passed, 0 failed, 11 skipped of 863; all Python script modules passed. Skips cover opt-in native media and live Workshop checks.
- Mechanical UI scan returned no findings. No desktop screenshots or visual run; no Release rebuild.

## 2026-09-30 — Consistent Settings spacing

- Promoted Storage spacing to shared Settings rules; preserved ongoing import-picker changes and changed no settings actions or native APIs.
- Offscreen Chrome: 140 layouts across seven Settings pages, four languages and five widths; no content overflow, narrow controls stack and switches remain inline, including expanded disclosures and long folder paths.
- Additional narrow-display smoke: day/night playlists and mirror mode had no overflow.
- Interaction smoke: keyboard disclosure toggling, snapshot-preserved slider draft and scroll, category navigation, full-width library path, action error recovery, and language/appearance availability without renderer settings observed using synthetic state.
- Impeccable detector on WebUI/settings.css returned no findings.
- python3 scripts/test.py --serial: passed, 855 passed, 0 failed, 11 skipped of 866; opt-in media/device and live Steam checks not run.
- Live app visual presentation unverified; no screenshots captured, desktop operations performed or Release app rebuilt.

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
