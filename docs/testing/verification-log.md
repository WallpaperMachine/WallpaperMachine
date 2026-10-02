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

## 2026-10-02 — Conditional texture masks contain brightness pulses

- `cargo test -p shader -- --nocapture` (renderer workspace, build environment): exit 0; 504 nominal successes, including 3 asset-dependent early-return skips, not 504 exercised cases. The new SPIR-V/MSL conditional-mask regression failed before the fix and passed after it; existing inactive-default and disabled-texture tests remain green.
- `python3 scripts/check_renderer.py --project <local-scene-project>`: exit 0; 502 native renderer checks passed, 3 optional corpus checks skipped; all ten generated scenes and the affected local scene matched pooled/isolated pixels with no diagnostics; two reload cycles passed. The GPU regression holds masked pixels constant across six alternating brightness frames while unmasked pixels continue changing.
- Surface-free before/after probes: same 30 frames at 1/60 s, fixed seed, untouched local package. Both pulse passes now retain their authored mask slot. Maximum consecutive-frame change in sampled mean red fell from 9.844 to 0.066 code values; both runs executed 540 passes. Masks add their intended texture residency/sampling, not extra passes or lower quality.
- `python3 scripts/test.py`: exit 0; Python modules passed; native gate 1064 passed, 0 failed, 12 skipped.
- `python3 scripts/build.py --configuration Release`: exit 0; local Release app rebuilt under the developer's build opt-in, not installed or launched.
- No desktop control, wallpaper changes, screenshots, audio devices or permissions. Desktop appearance, long-duration visual comfort and live power/frame-time performance remain unverified. Concurrent library/web/bridge/parallax edits were preserved; the gates and build used the shared working tree.

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

## 2026-10-01 — Steam and pixiv failure diagnosis

- Fixed unknown SteamCMD failures being attributed to credentials; classify compact network/rate-limit result names and log only a safe category.
- pixiv HTTP 403 now explains access denial rather than promising a one-minute wait; HTTP failures log status only, without URLs, cookies or bodies. Updated all four native locales.
- python3 scripts/test.py --only SteamCMDReportedFailureTests --only DownloaderLifecycleTests --only PixivServiceTests: passed 55, failed 0, skipped 0.
- First python3 scripts/test.py: Python passed; native 1036 passed, 1 failed, 11 skipped. WallpaperImportPickerTests/testCancellationReapsThePickerWaitingForASelection exceeded 120 seconds; no picker code changed.
- python3 scripts/test.py --only WallpaperImportPickerTests: passed 5, failed 0, skipped 0; timeout did not reproduce.
- Final python3 scripts/test.py: all 244 Python tests passed; native 1037 passed, 0 failed, 11 skipped (9 opt-in media tests, 2 live Steam tests).
- python3 scripts/build.py --swift-only --configuration Release: succeeded; app not launched or installed.
- The reported user's root cause remains unconfirmed without their diagnostics/network details. No live Steam login, live pixiv access or visual/desktop checks; unrelated workspace edits preserved.

## 2026-10-01 — PR 22 integration with current main

- Merged origin/main at e1fc9e1 into the native SteamCMD PR without rewriting history. The only conflict was the verification log; replayed the two PR-only entries through log_verification.py and asserted that both branches’ historical entries were preserved exactly, with ten active entries.
- `python3 scripts/test.py --only SteamCMDSetupTests --only SteamCMDApprovalTests --only LockScreenWallpaperServiceTests` — exit 0, 91 passed, none skipped.
- Full `python3 scripts/test.py` in the logged-in Aqua session — exit 0; 226 Python tests and 1,047 native tests passed, 12 opt-in skips. Ran the full gate once on the integrated tree.
- Skipped: nine opt-in media tests, two live Workshop-page cases and the live SteamCMD installer. No renderer/corpus, live account/CDN or desktop checks; no Release rebuild or production app restart.
- Resolved in the isolated PR worktree, leaving unrelated original-checkout edits untouched. git diff --check and staged conflict-marker checks passed.

## 2026-10-01 — PR 22 redirect-failure review fixes

- Addressed CodeRabbit and Claude: preserve a rejected redirect’s original failure if URLSession delivers its final response before cancellation; retain the isolated Foundation configuration copy with a narrowly documented SwiftLint force_cast suppression.
- Regression-first check: `python3 scripts/test.py --only SteamCMDSetupTests/testRejectedRedirectRetainsItsFailureWhenFinalResponseArrivesBeforeCancellation` failed before the fix by comparing original versus overwritten error values. It pins no localized wording and uses only URLProtocol fixtures.
- `python3 scripts/test.py --only SteamCMDSetupTests` — exit 0, 41 passed. Full `python3 scripts/test.py` in Aqua — exit 0, 226 Python tests and 1,042 native tests passed, 12 skipped; full gate ran once.
- Skipped: nine opt-in media tests, two live Workshop-page tests and the live SteamCMD install. No live account/CDN, renderer/corpus or desktop checks were run for this small download-delegate fix. SwiftLint is unavailable locally; its suppression was not verified with the lint executable.
- Verification ran on PR 22’s branch in an isolated worktree, leaving concurrent edits in the original checkout untouched. Coverage docs updated; git diff --check clean. No Release rebuild, production app launch/restart, security-setting changes or history rewrite.

## 2026-10-01 — Native Apple silicon SteamCMD package installation

- Full gate: `python3 scripts/test.py` in the logged-in Aqua session — exit 0; 226 Python tests and 1,041 native tests passed, 12 native tests skipped. Ran the full gate once.
- Gate skips: nine opt-in media cases, two live Workshop-page cases, and the opt-in SteamCMD install. Renderer/corpus and desktop/visual checks were not run; no renderer code changed.
- Targeted approval/runtime/downloader/queue/telemetry/WorkshopStore/ControlPanelShell runs with `python3 scripts/test.py --only …` — exit 0, 112 passed; remaining six ControlPanel classes — exit 0, 30 passed.
- `WALLPAPER_MACHINE_NETWORK_TESTS=1 python3 scripts/test.py --only SteamCMDSetupTests --only SteamCMDLiveInstallTests` — exit 0; 41 passed (40 offline setup regressions plus the live native installation), none skipped.
- Live install used temporary support/preferences/approval directories, real CDN packages, per-slice codesign and spctl, and the real native runner. Ready, arm64 resolution and Loading Steam API...OK were asserted; nothing installed into the user’s SteamCMD directory.
- Live checks exposed and fixed HTTP gzip Content-Length versus decoded-byte accounting and quarantined smoke exec being killed. Smoke now uses the downloader’s existing validated disposable-copy path; the installation candidate remains quarantined and policy failures are not bypassed.
- `spctl --assess --type execute --verbose=2` on the quarantined temporary native runtime returned 3 with valid-but-not-an-app, not the earlier sandbox’s internal error. All Mach-O slices verified and steamcmd satisfied Valve’s signing requirement; no system security settings changed.
- Authorized cached-session checks, using copied files and `arch -arm64`: sign-in without secret input, an active license listing app 431960, Workshop item 3773084716 downloaded successfully, and Windows app_update reached downloading then its owned process group was stopped. Temporary session copies were deleted, never written back.
- Localization: all ten changed native keys cover en/ja/zh-Hans/zh-Hant; panel localization passed in the gate. WebUI mechanical detector reported no findings; reinstall confirmation flow was inspected without desktop interaction.
- Owning feature/testing docs updated; Xcode project regenerated by test.py; git diff --check clean. Remaining risks: Valve changing/removing the package manifest and Intel-only copies needing reinstall. No Release rebuild, app launch/install/restart, wallpaper changes, or commit.

## 2026-10-01 — Preserve committed display mapping across lock-screen retry

- The reported timeout → missing display UUID → lock Retry → saver Off transition now invalidates only the lock request cache key, retaining the committed mapping needed for immediate Idle restoration.
- python3 scripts/test.py --only LockScreenWallpaperServiceTests --only LockScreenWallpaperTests — exit 0; 80 passed, 0 failed, 0 skipped. Includes pending lock recovery after the UUID returns without re-enabling the saver.
- python3 scripts/test.py — exit 0; 226 Python cases across 17 modules; native: 1036 passed, 0 failed, 11 skipped of 1047.
- Runtime smoke — temporary CLI linked current production Debug objects without the app entrypoint. With a software-generated silent video and isolated defaults/store, the missing-UUID transition restored original Idle immediately and removed the journal; exit 0. Temporary scaffolding removed.
- Owning feature and coverage documentation updated; relative links checked. No real WallpaperAgent reload, desktop changes, app launch, visual or power verification, or Release rebuild.

## 2026-10-01 — Keep screen saver selected when restored lock-screen activation times out

- Before fix: the restored-preferences regression failed (0 passed, 1 failed); after fix: all 33 LockScreenWallpaperServiceTests passed. The extra LockScreenWallpaperSelectionTests selector matched no class; the full gate below covered LockScreenWallpaperTests.
- python3 scripts/test.py — exit 0; all 17 Python test modules passed; native: 1035 passed, 0 failed, 11 skipped of 1046. Skips: 9 opt-in native-player media cases and 2 live Steam searches.
- Runtime smoke — temporary CLI linked the production Debug service/selection objects without the app entrypoint. A software-generated silent video, isolated defaults and wallpaper-store files exercised timeout retention, saver pause updates, lock disable and exact shutdown restoration; exit 0.
- Shared extension incompatibility, failed Idle-only publication, stale readiness and a later saver renderer failure remain covered by regression tests.
- No real WallpaperAgent reload, desktop changes, app launch, visual lock/idle transitions, or power measurements. The OS cause of the reported post-update missing lock-screen acknowledgement remains unverified; no Release rebuild requested.

## 2026-10-01 — PR 21 recovery journal review fix

- CodeRabbit: cancelled-quit synchronization and verification status findings were already addressed in 69fad27; fixed the remaining linked/inherited journal decoding finding.
- New linked and inherited baseline regressions reproduced both silent failures before the fix (targeted run exit 65); malformed arrays and invalid plist bytes now preserve the store and journal, skip reload, and recover after repair.
- python3 scripts/test.py --only LockScreenWallpaperTests: exit 0; 46 passed, 0 failed, 0 skipped.
- python3 scripts/test.py: exit 0; 226 Python tests and 1,031 native tests passed; 11 skipped (9 optional media and 2 live Workshop tests).
- python3 scripts/build.py --swift-only --configuration Release: exit 0; built the Release app containing the fix.
- Initial verification needed a test-fixture type annotation; sandboxed Xcode test-runner and compiler-plugin failures were resolved by rerunning with approved access outside the sandbox.
- git diff --check: exit 0. No renderer or generated-binding changes; desktop and visual behavior remain unverified. No app launch, install, restart, wallpaper change or live account access.
