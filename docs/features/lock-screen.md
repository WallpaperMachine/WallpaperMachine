# Animated lock screen (experimental)

The app can animate the macOS lock screen. The feature is off by default.

## Enabling it

Apply a video or live scene to a display, then enable **Settings -> General ->
Animate lock screen**, or the same switch on the welcome guide's Preferences
page (it applies at once there too; the guide's **Skip** turns it back to what it
was when the guide opened). A status row next to the Settings switch reports the
current state, and a **Retry** action appears when activation failed.

This uses a sandboxed native wallpaper extension — the
[`Extension/`](../../Extension) ExtensionKit target — rather than drawing an
ordinary app window over the login UI. While it is active the native desktop
remains a still frame, while the existing desktop renderer keeps playing.
Once its first frame is ready, an unlocked lock-screen surface retains its
captured poster and releases the renderer, textures and device allocations.
The poster image retains the read-locked snapshot IOSurface until Core Animation
releases the image, so it does not keep a separate copy of the same pixel buffer.
Locking again reloads the scene behind that poster before resuming animation.
This saves memory while unlocked; a cold lock may briefly show the still frame,
and animation/script state starts again. Resolution, frame rate and effects
are unchanged. A failed reload keeps the poster and reports readiness failure;
it does not repeatedly retry until a new unlock/lock cycle or scene replacement.
User pause, display sleep and host suspension still prevent a reload.

Lock-screen audio, audio input and media integration are disabled; see
[Audio response](audio-response.md) and
[Media integration](media-integration.md). The extension turns media off again
after `apply_config`, so a desktop Scene that uses now-playing does not keep
that feed on the lock screen.

"Enabled" is not claimed optimistically: it requires the system extension to
acknowledge a rendered frame. The extension answers macOS only once that frame
exists, and WallpaperAgent abandons an extension that has not answered after
about 31 seconds (observed on macOS 27.2), so a scene must reach its first frame
well inside that; see
[startup costs](../testing/renderer.md#startup-and-staging-buffers).

## Caveats

- It requires macOS 26 or later. On earlier releases the app does not start the
  service, Settings reports "Requires macOS 26 or later", and the extension
  refuses the system's connection: the private protocol it speaks has only been
  verified on macOS 26 and 27.

- Lock-screen animation uses private macOS wallpaper APIs and wallpaper-store
  formats that may change; it may stop working after an OS update, and rendering
  is not guaranteed on every macOS release.
- It replaces the Desktop and Idle provider on active wallpaper displays and
  reloads the wallpaper service.
- System-wide linked wallpapers, or another wallpaper app, can prevent
  activation. The app reports the conflict instead of overwriting those choices.
- Playback respects the pause and battery settings. The lock screen covering the
  desktop does not pause it.

## When activation fails

If the renderer fails, or misses the extension's own 30-second first-frame
deadline, the extension writes the reason to its readiness file and the status
row shows it. The generic "macOS did not load the lock-screen renderer" message
means no answer arrived at all. The extension keeps a bounded log at
`~/Library/Application Support/WallpaperMachine/LockScreenExchange/extension.log`.
The app and extension exchange files only there, never through the extension's
sandbox container, so macOS does not ask the app for access to another app's
data. Files earlier releases left in that container are removed by the extension.

Every copy of the app on disk registers the same extension identifier, and
macOS may launch any of them — including the Debug build `scripts/test.py`
rebuilds beside the Release app.
`pluginkit -m -A -D -v -i app.wallpapermachine.wallpaper-extension` lists every
registered copy (without `-A -D` it shows only one); keep one while testing.
After testing copied app bundles, unregister their `.appex` paths with
`pluginkit -r` and stop keeping those copies as launchable `.app` bundles.
Verify the running extension's executable path points inside the installed app;
checking only the bundle identifier does not establish which copy macOS chose.

## Turning it off

Disabling the feature or quitting the app restores the native selections that
are still owned by this app. Wallpaper changes made elsewhere are preserved.

## Background checks and recovery

The service keeps one two-second monitor only while animation is requested,
recovery is complete, shutdown has not begun, and no error is pending. Busy
refreshes keep that timer but skip its work. An active request with no scenes
still checks for a later wallpaper; disabling or shutting down cancels the timer
immediately. An error stops automatic monitoring until an explicit retry or
another existing refresh path succeeds.

Recovery entries represent the last successful journal commit. Repeated checks
  do not rewrite an unchanged journal, but still read the actual system store to
  detect new Spaces and external selections. Unchanged inputs skip the
  compatibility check. A revision-only store update may
still require a wallpaper-service reload without rewriting the journal. The
recovery union is persisted before changing the store, and pruned only after a
successful reload; failed writes, reloads or journal removal retain recovery
information for retry.

macOS copies the extension's selection into the fallbacks it reloads
(`SystemDefault` and each Space's `Default`), and a Space created while the
feature is on, a new desktop or a full-screen app's, starts from those copies,
so the live store has no native choice left to restore it to. Such a Space is
taken over like any other, with originals taken from the journaled originals
of those fallbacks, and restored to them when the feature turns off. A Space
created after the last check, just before the feature turns off, was never
journaled; turning off still restores its Default and the journaled displays'
nodes the same way, and keeps the journal for a retry if nothing native is left
to restore them to. Before 2026-09-28 the first check after a new Space failed
with "no restoration journal or surviving system fallback", turned the feature
off and left that Space pointing at the extension.

## Storage

Lock-screen assets are isolated copies, using APFS clones where available. They
still require additional disk space.

## Verification

See [Testing](../testing/README.md) for the exact tested behavior and visual
limitations, and the [verification log](../testing/verification-log.md) for
recorded runs.

Back to the [project README](../../README.md).
