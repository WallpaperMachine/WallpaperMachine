# Verification log archive — 2026-10 and earlier

Retired entries from [../verification-log.md](../verification-log.md), moved
here when that log was capped at its ten newest entries. No recorded result was
rewritten: each entry is reproduced verbatim, and the only edit is that
relative Markdown links gained one `../` for this file's extra directory
level.

These are historical results about the trees they were taken on. They are not
evidence about the current tree and must never be cited as such.

## 2026-10-01 — Bounded HDR and interactive scene compatibility

- User selected a general bounded bloom model rather than claiming exact proprietary Wallpaper Engine HDR parameter parity. No wallpaper-specific rendering branches or private asset edits.
- cargo test --release -p shader --features ffi with the build cargo environment: exit 0; 522 passed. Fourth-channel metadata and disabled-slot behavior covered.
- Targeted CMake build and text/script/mouse/scene/texture suites: exit 0; 60, 84, 13, 89 and 22 passed respectively; two opt-in local text cases skipped. Particle suite: 41 passed. Diagnostic dumper library compiled.
- GPU HDR filters: four passed, including real TEX bit23 emissive radiance through effects/linked layers, SDR preservation, missing-source rejection, bounded spread, live strength changes and zero halo strength.
- Installed perspective scene: both Metal and Compatibility completed 1200/2400 frames at 1/60 and 1/120 simulation steps, 1680x1050, synthetic clock click/hover entry/exit and broadband audio. Sampled script errors zero; menu and overlay transitions, moving bars/waves and numeric readouts verified.
- Full-resolution scenarios: Native Metal 1200 frames and Compatibility 2400 frames at 3840x2160 completed; sampled input transitions and script errors passed. Offscreen frames visually inspected; no desktop capture or audio hardware used.
- Native drawFrame CPU means: 0.60 ms at 1680x1050, 0.59 ms at 3840x2160. These exclude script tick/GPU/display cadence and are not FPS or power claims; HDR half-float target cost is documented, with no forced supersampling.
- python3 scripts/test.py --serial: exit 0; all 17 Python modules passed; native 883 passed, zero failed, 11 opt-in skips of 894.
- python3 scripts/check_renderer.py: isolated final run exit 0; all renderer executables passed, ten generated pooled/isolated comparisons equal with zero diagnostics, eight projects reloaded twice. Three default opt-in asset checks skipped; target scene exercised separately. Earlier concurrent run failed one baseline video-frame timing assertion; retained assertion passed on the isolated full rerun.
- Documentation links and provenance JSON checked. No Release app rebuild, launch/restart, live settings changes or desktop input. Exact Windows visual equivalence, physical presentation cadence and power effects remain unverified.

## 2026-10-01 — Lock-screen extension mismatch diagnostics

- Added revision-scoped extension identity, schema-version and configuration-load diagnostics; legacy extension copies are identified by running bundle path after readiness timeout.
- python3 scripts/test.py --only LockScreenExtensionDiagnosticsTests --only LockScreenWallpaperServiceTests: exit 0; 31 passed before the final screen-saver monitor regression was added.
- python3 scripts/test.py: exit 0; all 226 Python tests passed; native gate 898 passed, 0 failed, 11 skipped of 909. Includes all 10 new diagnostic regressions.
- Native skips: nine opt-in media/device tests and two live Workshop network tests. No asset-dependent renderer checks were run; renderer and bridge were unchanged by this task.
- Covered incompatible schema before scene decoding, missing/malformed configuration, stale revisions, same-bundle symlinks, configuration success without frame readiness, failed diagnostic writes, legacy timeout restoration and later screen-saver configuration failure.
- git diff --check: exit 0. XcodeGen regenerated the project through test.py; native localization checks passed in the gate.
- python3 scripts/clean.py --dry-run: exit 0; broad cleanup deferred to preserve the shared workspace renderer evidence under artifacts.
- No Release rebuild, app restart, registration changes or desktop tests. Live extension selection and lock-screen visuals remain unverified.

## 2026-10-01 — PR 19 backup and preset review fixes

- `python3 scripts/build.py --renderer-only` — passed; rebuilt the isolated worktree’s missing current bridge library and regenerated unchanged bindings after the first targeted run could not link.
- `python3 scripts/test.py --only WallpaperBackupTests --only WallpaperPresetStoreTests --only ControlPanelBackupFlowTests` — passed, 50 tests; an earlier run exposed volatile-default cleanup in the new fixture, corrected before this run.
- `python3 scripts/test.py` — passed once as the final gate: all Python checks passed; 1006 native tests passed, 0 failed, 11 opt-in media/network cases skipped.
- Regressions cover persistent-only preference export/conflicts/rollback, a 48 MiB preset archive, manifest rejection before payload reads while preserving an existing destination, and preset directory roundtrips with hidden Finder metadata.
- The WebUI mechanical detector reported no findings; `git diff --check` passed. No renderer source or generated-binding changes.
- No Release app build, desktop/window-driving, visual presentation, audio hardware or live-account verification. The shared main checkout’s existing commit and uncommitted edits were not changed.

## 2026-10-01 — Reusable wallpaper workflows rebased onto 1.2.1

- Implementation: local collections and named playlist plans, wallpaper property presets, staged local backup/restore, per-display still-image placement, compatibility cards, Shortcuts display selection, and Web page mute/native HTML-media gain; all four UI languages updated.
- Fetched origin and rebased feat/library-workflows-and-web-audio onto main a5200fe; preserved remote import-picker startup, screen-saver/renderer updates, localization and historical verification records. Regenerated Xcode project and UniFFI outputs rather than editing generated conflicts.
- Scene restore security: scene/scenetexture overrides and texture defaults now resolve to validated retained image files instead of unapproved original paths. A keep-existing tree without matching bytes is rejected before publication. WallpaperBackupTests: 24 passed before rebase; included again in the rebased full gate.
- python3 scripts/build.py --renderer-only — exit 0 after rebase; renderer library and Swift bindings regenerated. No Release app build.
- cargo test -p wallpaper-bridge with scripts/build.py cargo_environment — exit 0 after rebase; 363 passed, 0 failed.
- python3 scripts/check_renderer.py — rebuilt current renderer probes, exit 0; 10 generated scene pixel comparisons and 8 projects x2 reload cycles passed. Three local-asset-dependent cases skipped; no full authored-wallpaper compatibility claim.
- python3 scripts/test.py — exit 0 after rebase; all Python checks passed, 1002 native tests passed, 0 failed, 11 opt-in media/network tests skipped of 1013.
- Before rebase: six temporary real offscreen WKWebView feature flows passed and were removed after retaining focused regressions; renderer draft/metadata and synthetic pointer-capture boundaries were injected. Native WebKit output probe invoked media gain and read back mute false→true→false without audio hardware.
- Desktop/visual presentation, actual speaker output, live account services, Siri/Shortcuts UI and power remain unverified. No app launch, permission prompt, wallpaper change, install or restart.

