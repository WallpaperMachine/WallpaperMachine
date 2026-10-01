# Verification log archive — 2026-10 and earlier

Retired entries from [../verification-log.md](../verification-log.md), moved
here when that log was capped at its ten newest entries. No recorded result was
rewritten: each entry is reproduced verbatim, and the only edit is that
relative Markdown links gained one `../` for this file's extra directory
level.

These are historical results about the trees they were taken on. They are not
evidence about the current tree and must never be cited as such.

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

