# Web wallpapers

Wallpaper Engine projects with `"type": "web"` are HTML pages (`"file"` names the
entry page, usually `index.html`) that talk to their host through
`window.wallpaperPropertyListener`. WallpaperMachine renders them in a
`WKWebView` hosted by the app; the vendored scene renderer never opens a window
for them.

## What the user sees

- [Live preview](control-panel.md#live-preview) runs an installed project in its
  own window and temporary website data store, with independent playback and
  default mute. It never replaces the desktop page or its stored state.
- Web wallpapers import, download and apply like scene and video wallpapers, and
  their user properties (combos, sliders, colors, text, booleans) are edited in the
  same inspector. Apply pushes the committed values into the running page.
- Play/Pause, the presentation policy (occluded desktop, display sleep, session
  lock), display assignment, mirroring, and Space posters apply to web wallpapers
  the same way they apply to renderer wallpapers. Occlusion is per display: a
  window covering the wallpaper on one screen suspends that page and leaves the
  page on another screen running.
- The Workshop badge reads *Web · built-in web view*; the inspector notes that
  mouse input and audio response reach the page while keyboard input does not.
- Mouse input reaches the page: hover, clicks, drags, right clicks and scrolling
  over the desktop are mirrored into the wallpaper. Finder keeps its icons and
  the desktop keeps every system behavior, so a click on an icon also reaches
  the page. Settings › General › *Keep windows in place when clicking the
  wallpaper* turns off macOS's "Click wallpaper to reveal desktop" option (the
  same value System Settings › Desktop & Dock writes) so a click no longer
  slides every window aside.
- On macOS 26+, **Use wallpaper as screen saver** can present web and still-image
  projects through the native extension. It uses committed properties and isolated
  file copies, without audio, capture or interaction. See
  [Screen saver](lock-screen.md#use-wallpaper-as-screen-saver) for activation,
  independent selection and verification limits.

## Host protocol

The page is loaded from `file://` with sibling-file access, matching Wallpaper
Engine's CEF host: ES modules, `fetch()` and media inside the project folder work,
and `location.protocol` is `file:`. WebKit resolves a `fetch()` of a project file
with status 0, `ok === false` and no headers, where Chromium answers 200 with a
`Content-Type` from the extension; the host script gives a found `file://` GET/HEAD
response that status and type (body streamed through, missing files still reject),
so WebGL exports such as Unity and Emscripten, which check `ok` and stream `.wasm`
into `WebAssembly.instantiateStreaming`, start. Those served `.wasm` responses are
compiled from their bytes rather than by WebKit's streaming compiler, which
measured about 190 ms slower to boot a 22 MB Unity module; every other response
keeps WebKit's native streaming and MIME check. Local XMLHttpRequest responses
also expose `200 OK` once WebKit supplies a file response URL, including inside
ready-state callbacks and immediately after a synchronous `send()`. Unopened,
missing, failed and aborted requests retain native status 0; non-file responses,
bodies, decoding and event delivery stay native. This only adapts metadata reads:
there is no body copy, retry loop or per-frame work.
A document-start script installs the host side:

| Call into the page | When |
|---|---|
| `wallpaperPropertyListener.applyUserProperties({ id: { value } })` | After load and after every Apply; colors are `"r g b"` floats in 0–1 as in `project.json` |
| `wallpaperPropertyListener.applyGeneralProperties({ fps })` | After load and when the display's target FPS changes |
| `wallpaperPropertyListener.setPaused(bool)` | Play/Pause, presentation suspension |
| `wallpaperPropertyListener.userDirectoryFilesAddedOrChanged(property, files)` / `userDirectoryFilesRemoved(property, files)` | A watched `fetchall` folder gained or lost files |

Combo values reach the page with the selected option's authored JSON type: a
numeric option stays a number, a boolean stays a boolean, and a string such as
`"3"` stays a string. The inspector and saved overrides still use string selection
keys; conversion happens only when exporting the Web payload. This keeps strict
JavaScript comparisons and `switch` statements working without guessing types
from numeric-looking text.

Property positions are ordering hints, not identity. Fractional `order` values
are preserved, and distinct property IDs with the same `order`/`index` are all
retained in declaration order, including properties with no position specified.

Values are replayed to a listener that registers after the first push, so pages
that install the listener from a deferred module still start correctly. The top
frame cannot navigate away from the entry page; subframes and network requests are
unrestricted (macOS ATS applies, so plain `http://` requests fail).

The author-facing APIs are installed on the wallpaper web view at document start.
A page may call `wallpaperRegisterAudioListener`, the five
`wallpaperRegisterMedia*Listener` functions and
`wallpaperRequestRandomFileForProperty`. `window.wallpaperMediaIntegration`
exposes the playback constants under both documented spellings:
`PLAYBACK_PLAYING` / `PLAYBACK_PAUSED` / `PLAYBACK_STOPPED` and
`playback.PLAYING` / `.PAUSED` / `.STOPPED`, with values 0, 1 and 2.

Registering a listener replaces the previous one rather than adding to it, and
each listener fires only when its own part of the state changed. A page that
registers after the document loaded is given the current state, so an
asynchronously registered listener still starts.

Audio, media and directory delivery all stop while a page is suspended and
resume when it comes back. Media state is re-derived on resume; directory
additions and removals are ordered, so they are held across the suspension and
replayed rather than collapsed.

The wallpaper web view has exactly one `WKScriptMessageHandler`, named
`mweWallpaper`, carrying listener registration and random-file requests. It is
removed when the page stops. It is not the control panel's channel; `WebUI/` is
a separate web view with its own handler.

## Runtime shape

- Rust (`crates/bridge`): `WallpaperProjectType::Web` entries are `supported`.
  `ActivationInputs::build()` routes web projects away from the scene engine and
  `build_web()` yields one `WebWallpaperDesc` per assigned display (mirrors
  included). The uniffi call `web_wallpapers()` exposes them as
  `BridgeWebWallpaper` (display id, project path, entry file, fps, paused,
  effective property values as the `applyUserProperties` payload). Active ids
  include configured web wallpapers; lock-screen scenes never do.
- Swift (`App/Services/WebWallpaper/`): `WebWallpaperHost` re-reads
  `webWallpapers()` on every snapshot and diffs it against one
  `WebWallpaperWindow` (`MWEWebWallpaperDesktopWindow`, desktop level, all Spaces,
  mouse-transparent) per display. `WebWallpaperPage` owns the `WKWebView`, the
  host script, property/pause delivery, host-side suspension and
  content-process recovery.
- Suspension does not rely on the page cooperating. `setPaused` is an optional
  listener callback, so a page can ignore it; alongside it the host suspends all
  media playback (suspend and unsuspend, so media the user had paused is not
  started by a resume) and removes the web view from the window tree, which is
  the documented condition for `WKPreferences.inactiveSchedulingPolicy`
  (`.suspend`). A snapshot taken before detaching stays on screen as a
  placeholder inside the window's container view, so the Space poster sync keeps
  identifying the surface by the same content layer, and a suspended page
  receives no pointer events. The document is never reloaded to suspend it, so
  its JavaScript state survives. How much WebKit then throttles the page is its
  own decision and has not been measured here.
- While attached, a desktop page leaves window-occlusion decisions to
  `WallpaperPresentationPolicy`. A guarded per-view WebKit selector disables
  WebKit's independent window-occlusion check; otherwise even a brief Space or
  Show Desktop transition can stop animation frames before the host's settling
  delay expires. Host suspension still detaches the view and retains `.suspend`
  scheduling. If that selector is unavailable, the page retains WebKit's default
  scheduling and logs the limitation. This does not change the control panel or
  native screen-saver web surfaces.
- A content process that keeps terminating is restarted on a windowed budget
  with exponential backoff rather than forever; the budget returns only after a
  document has run without interruption for the stable-run threshold.
- Committed host state (properties, fps, pause) is replayed in full on every new
  document, so a reload after a crash restores the page even though nothing in
  the descriptor changed.
- The inspector reports each display's loading, ready or failed host state.
  A failed live Web page offers **Retry wallpaper**. Project validation and file-scan
  failures display their error without offering a retry that cannot reload a page;
  fix the project and refresh or reapply it. Late callbacks from a replaced
  surface are ignored. The host echoes the bridge's startup revision only after
  loading finishes (or fails); accepting an assignment does not imply ready content.
- A library refresh checks active project file identities on a background actor.
  Replacing HTML or resources at the same path reloads the page even when an
  intermediate empty assignment was coalesced away. An unchanged revision keeps
  the existing document. Managed-asset changes also invalidate native publication.
- Mouse input (`WebWallpaperMouseForwarder`): the windows stay mouse-transparent
  and nothing is consumed, so no Accessibility or Input Monitoring grant is
  needed. The global `NSEvent` monitor is installed only while at least one page
  is loaded and not host-suspended (`WebWallpaperHost.refreshPointerMonitor`);
  a window whose page has not loaded, and a page the host has suspended, install
  none. While it is installed it observes desktop pointer events;
  `WebWallpaperMouseRouting` forwards them only while the window the system
  would hit is below layer 0 (Finder's desktop, the system wallpaper, widgets),
  keeps a forwarded press's drags and release, and sends one exit when the
  pointer leaves the desktop. The hit window is the one the window server
  recorded in the event (`kCGMouseEventWindowUnderMousePointer`), so routing
  makes no window-server call per move. A synchronous
  `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)` per move stalled the
  main thread during Show Desktop, and with it the page's layer commits, which
  WebKit applies on the main thread: the web wallpaper froze while scene
  wallpapers, drawn on their own thread, kept running. Only a press or scroll
  without the field still asks (scroll-wheel events may not carry it); a move
  without it is dropped. Window layers are cached per window number. Events
  are rebuilt in wallpaper-window coordinates (`NSEvent.mouseEvent`; scroll
  wheels copy their `CGEvent`) and replayed through the responder methods. Hover has no public entry point on
  `WKWebView`, so it uses `_simulateMouseMove:`/`_simulateMouseExit:` when the
  running WebKit responds to them, and `WebWallpaperWindow` reports
  `isKeyWindow` as true because WebKit hit-tests hover only for active windows
  (the window still cannot become key, so keyboard focus is never taken).
  The host script cancels `contextmenu` defaults so WebKit's own menu never opens.
- `DesktopClickRevealPreference` (`App/Services/Desktop/`) reads and writes
  `com.apple.WindowManager EnableStandardClickToShowDesktop` for the Settings toggle.
- `WallpaperPresentationPolicy` counts both window classes when deciding whether
  a wallpaper pixel is visible; `DesktopWallpaperSync` asks a web surface for a
  `WKWebView` snapshot through the same poster request it sends to Metal layers.

## Audio response

Per wallpaper, off unless the user turns it on in the inspector's *General
configuration*. The switch is consent to capture, not a promise of delivery: the
page receives nothing until it calls `wallpaperRegisterAudioListener`, and a
wallpaper that never asks stays silent however the switch is left. The panel
reports this wallpaper's state from the running host: requesting a connection,
confirmed subscription, or successful delivery of a valid frame to its JavaScript
listener. A frame older than two seconds no longer counts as current delivery.
A failed subscription tells the user to toggle and retry; another wallpaper's
subscription never changes this one's status. With no running surface, delivery
remains unknown. A page that has not registered a listener is reported separately.

The listener receives the documented 128-float array: indices 0–63 the left
channel, 64–127 the right, low index first within a channel. Delivery is capped
at 30 Hz, skips generations the analyser did not recompute, and happens only
while the page has a registered listener, the user has audio response enabled for
that wallpaper, and the page is not suspended. One shared poller serves every
display and does not exist while nothing is subscribed; the system capture tap is
opened and closed from that same demand, and a page counts as a consumer only
once it has subscribed. Mute and volume do not affect it: a silenced wallpaper
still analyses what the system is playing.

Capture uses a CoreAudio process tap created with
`initStereoGlobalTapButExcludeProcesses:` and is genuinely two-channel — left and
right are analysed by separate FFTs. If that initialiser is absent or the created
tap reports fewer than two channels, capture falls back to a mono tap, left and
right are then equal, and nothing reports that as stereo. The spectrum's `stereo`
flag describes how the PCM was submitted, not whether the content happens to
differ. Values reaching the page are clamped to 0.0–1.0 by the renderer's
spectrum entry point; the official protocol says values may occasionally exceed
1.0 and tells pages to clamp themselves, so this is a documented deviation rather
than a match.

## Media integration

Off by default, per wallpaper. Web pages still register
`wallpaperRegisterMedia*` listeners as documented above. The now-playing source
is shared through `DesktopMediaSession` and also feeds Scene wallpapers that
have the same toggle on. Sources, lifetime, lock-screen policy and tests are
documented in [media-integration.md](media-integration.md).

The status listener describes the user's setting, independently of provider
availability. With integration enabled but no data, properties are empty,
playback is stopped and there is no timeline. An empty thumbnail string clears
the previous cover. Pages must tolerate absent metadata and timelines.

## User-selected files and folders

`file` and `directory` wallpaper properties let the page read a file the user
chose from anywhere on disk. A `WKWebView` only grants `file://` reads below the
root passed to `loadFileURL(_:allowingReadAccessTo:)`, and that root has to be an
ancestor of the entry page, so a page can never read outside its own project
folder; widening the root to a common ancestor would hand every wallpaper the
whole application-support tree. A symlink placed inside the root is resolved by
WebKit and refused, a hard link is not. Both were measured, and together they fix
the design.

- `App/Services/UserAssets/ManagedUserAssetStore.swift` holds the app's own copy of
  each chosen file under `~/Library/Application Support/WallpaperMachine/UserAssets/`
  (`WALLPAPER_MACHINE_HOME` relocates it), laid out as
  `<stableWallpaperId>/<propertyId>/<assetId>/<fileName>` with a `manifest.json` per
  wallpaper. The manifest, not the wallpaper package, is the system of record: it
  records the asset id, the user's original path, the size, the modification time, a
  SHA-256 content digest, and whether the import was a file or a folder. Keying on the
  stable wallpaper id rather than the display name or entry file name is what lets an
  import survive a Workshop update or a delete-and-re-download. Importing clones the
  user's file with `clonefile` where the filesystem supports it, and copies otherwise;
  the user's original is never moved, renamed or written to.
  New records retain the full modification time in optional `modifiedReferenceTime`
  alongside the legacy ISO-8601 `modified` field, so an unchanged selection can skip
  hashing after relaunch. Older manifests remain readable without a version migration.
- `App/Services/UserAssets/UserAssetStore.swift` keeps a **derived** bridge at
  `<project>/.mwe-user-assets/<propertyId>/`, as a hard link onto the store's copy when
  the project shares its volume and a byte copy when it does not. The bridge exists only
  because of the WebKit read-access rule above, and holds nothing of its own: deleting
  all of it loses nothing, because the next import rebuilds it from the manifest. Data
  flows store → bridge only. No authored wallpaper file is touched; the dot directory is
  the only thing created inside the project.
- A round-6 staging directory is absorbed into the store once, and only when the
  property's original source no longer resolves. Nothing in the old location is deleted,
  and the manifest records that the migration happened, so it never runs twice. If the
  copy or the record fails, the old staged entry is still exactly where it was and still
  loads.
  A bridge this build writes drops a hidden `.managed-by` naming the wallpaper it
  belongs to, so a different wallpaper id cannot mistake it for a round-6 staging
  directory and adopt files that are not its own. A genuine round-6 bridge has no such
  marker, which is exactly what makes it migratable.
- An asset whose original path no longer resolves but which is still in the store stays
  usable, served from the store. One that is in neither place is reported as missing —
  `assetMissing` on the property descriptor — rather than silently cleared.
- The value handed to the page is the staged absolute path with its leading `/`
  removed and `%`, `#` and `?` percent-escaped, so the page's `'file:///' + value`
  resolves. Spaces, non-ASCII, `+`, `&` and `'` are left literal, because a page
  that treats the value as a plain path must still see them.
- Only image (`jpeg jpg png pnga bmp gif svg webp`) and video (`webm ogg ogv`)
  extensions are staged, case-insensitively; a property that declares no file type
  accepts the union of the two, never an arbitrary file. A folder is read one level
  deep and capped at `UserAssetStore.defaultDirectoryFileLimit` (4096) entries;
  hitting the cap is reported rather than silently dropping files.
- A `fetchall` folder is watched with FSEvents, never polled. A burst of changes is
  debounced into a single added/removed diff, which re-stages added or rewritten
  files, drops the links for removed ones, and reaches the page as
  `userDirectoryFilesAddedOrChanged` / `userDirectoryFilesRemoved`.
  An unavailable directory or unreadable matching file preserves the last committed
  list and bytes until a successful scan. A failed manifest write also preserves them;
  pruning and removing bridge entries happen only after the new manifest is durable.
- Lifetime: the store outlives the project, the bridge outlives the process, the
  in-memory index does not. `WebWallpaperHost` re-imports on next use — which is what
  rebuilds a missing bridge — and discards the store handle for a project nothing
  displays any more. Changing the pick replaces that property's assets in both places;
  clearing a property removes them from both.
  `python3 scripts/clean.py --user-assets` removes every `.mwe-user-assets` bridge in
  the imported library and the Steam workshop folder, which the app rebuilds on next
  load. `python3 scripts/clean.py --managed-user-assets` is the destructive one: it
  deletes the app's own copies, which nothing regenerates. Neither the default pass nor
  `--all` nor `--derived` reaches either of them.
- `UserAssetWorker` performs enumeration, hashing, copying and bridge publication
  outside the main actor. A newer selection cancels the previous preparation.
  A shared asynchronous turn per managed root and wallpaper serializes preparation,
  publication, permission changes and purge across store instances. Copies publish
  from operation-owned temporary files, and cleanup reads the latest manifest.
  The manifest commit compares the property's original version and merges unrelated
  property edits; stale preparations cannot overwrite a newer selection. Selecting
  the same path explicitly invalidates the host's staging cache, while ordinary
  unchanged reconciles keep using it. Watcher callbacks are scoped to their selection.
  All store instances share an asynchronous turn queue for each canonical managed
  root and wallpaper ID. A turn covers preparation through bridge publication;
  permission grant/rollback and cache purge use the same queue. Different wallpapers
  can prepare independently, and waiting never blocks the main actor. Content copies
  use private temporary files before atomic publication, so cancellation cannot delete
  another import's copy. Cleanup re-reads current manifest references and removes
  retired trees outside the short metadata lock. Permission transactions release their
  turn before awaiting an engine mutation, then merge rollback with current records.
- The control panel's Storage row shows the managed directory, reveals it in Finder, and
  offers a purge that reclaims only stored bytes no manifest still lists — an orphaned
  `assetId` folder, a property the manifest no longer mentions, a wallpaper folder with
  no manifest. A referenced asset is never a purge candidate, which matters most for the
  property whose original has gone and whose stored copy is now the only one.
  A missing manifest is distinct from an unreadable, damaged, foreign or unsupported
  manifest. The latter prevents that wallpaper's files from being purged or replaced.
  Purge logs and skips the affected wallpaper while continuing to reclaim other
  unreferenced files; cancellation still stops the operation. Clearing a property
  likewise commits its removal before deleting
  its retained bytes.
- The lock-screen extension is sandboxed
  (`Extension/WallpaperExtension.entitlements`) and cannot read either the store or the
  bridge. For a committed **video or scene** wallpaper, the assets that wallpaper
  actually references are republished into the lock-screen exchange directory as their own
  `revisions/<fingerprint>/` tree and the property values are rewritten to
  point at that copy; the fingerprint is taken over the recorded content digests, so an
  unchanged selection is recognised and nothing is copied again. Revisions the published
  configuration no longer names are collected after each successful publish.
  **Web** wallpapers have no lock-screen support at all: that combination is reported as
  not applicable, never as a failure.

### In the inspector

A `file` property shows a read-only field with the chosen file's own name — never
the staged path the page reads — a *Choose…* button, a *Clear* button, and the
extensions the property accepts, taken from its `fileFilter`. An absent filter
means the author declared no file-type option, which the protocol defines as both
kinds it knows, so both lists are offered.

A `directory` property adds how many files in the chosen folder the importer would
take, whether the folder holds more than the import limit, and what the wallpaper
does with them: a `fetchall` folder is handed to the page whole, an `ondemand`
folder is one the page picks from itself. The count is the panel's own measurement
of the chosen folder, applying the same screens the importer applies — first level,
accepted extensions, no hidden entries, regular files only, readable only — and it
is kept until the chosen path changes, so a folder is not walked on every
re-render. It describes the folder, never the outcome of an import the panel cannot
observe: a single entry whose link and copy both fail is skipped and logged by the
importer. A folder that cannot be read is reported as unreadable rather than as
empty.

Both persist through `setPropertyPath`; *Clear* sends `nil` and the engine writes
the property's own default back. A choice the app cannot honour — a wallpaper
folder that is missing or read-only, so nothing can be staged inside it — is
reported beside that control rather than in the window-wide banner, and the path
is not sent. `texture` and `scenetexture` properties are a separate kind: they keep
the scene texture picker they always had and are refused by the path editor.

## Page sound

Mute and Volume now reach the page's output, independently of Audio response.
`WebWallpaperAudioOutput` resolves WebKit's native interfaces at runtime:
`WKPageSetMediaVolume` controls HTML audio/video media elements, while
`_setPageMuted:` with only the audio bit controls whole-page output, including
WebAudio. Nonzero Volume is **not** a WebAudio gain control. Zero volume also
mutes the page; neither control pauses media timelines or disables system-audio
analysis. The official general-property payload remains `fps`, not an invented
`volume` protocol.

User mute and temporary app/Focus/other-audio mute compose in the existing bridge
configuration. Ending a rule does not clear user mute. Mirrored pages elect one
presenting audible owner per actual source assignment; independent assignments
of the same project remain independent. A hidden owner hands off to a visible
mirror without producing duplicate sound.

These are private WebKit interfaces and may be unavailable on another macOS
version. **Audio and media status** reports the observed availability; it never
substitutes Pause for unavailable mute. Windowless verification exercises setter
and mute-state readback without starting audio hardware; actual speaker output
and audible handoff require an authorized desktop/audio run.

## Not yet supported

- Keyboard input is not forwarded; the wallpaper window never becomes key.
- Pointer events are mirrored, not captured: Finder still selects icons and
  rubber-bands, and a click on an icon reaches the page too. The middle button
  arrives without its button number.
- Nonzero WebAudio gain is not controlled by the native media-volume interface;
  whole-page Mute still applies where WebKit exposes it.

## Verification

`Tests/Unit/WebWallpaper/WebWallpaperPageTests.swift` drives a real offscreen
`WKWebView` (no desktop window): module loading from the project folder,
late-listener replay, pause composition, top-frame navigation lockdown, and
forwarded clicks and right clicks reaching page listeners with the native
context menu suppressed. `WebWallpaperMouseRoutingTests.swift` pins the
desktop-only routing policy and that a move, press, drag or release carrying
its window never queries the window server; the field's agreement with the
synchronous query on real desktop events was checked by hand, not by a test.
`WebWallpaperLocalRequestTests.swift` covers
synchronous startup loaders, empty successful responses, async ready-state
metadata, JSON/binary bodies, missing files, cancellation and request reuse.
`WebWallpaperSuspensionTests.swift` also supplies occlusion changes through a
window that is never ordered on screen: a running page keeps producing animation
frames until the host suspends it, and the existing detach/reattach checks cover
host suspension without reloading the document. This is not a measurement of
WindowServer transition smoothness on the real desktop.
`Tests/Unit/Panel/WebPanelAssetPropertiesTests.swift` covers the inspector side:
what `Choose…` and `Clear` send, the refusal of a `texture` property by the path
editor, the folder measurement published to the page, and a chosen name carrying
markup reaching the DOM as text.
`crates/bridge/src/tests/apply_options.rs::web_wallpaper_apply_bypasses_engine_and_exports_host_inputs`
proves the bridge contract. The companion
`web_wallpaper_combo_values_keep_authored_types_after_editor_changes` regression
checks typed defaults and committed editor selections; the manifest regression
`web_wallpaper_property_order_preserves_fractional_and_shared_positions` checks
that fractional and shared positions do not discard settings.
Desktop behavior needs an authorized manual run; see
the [verification log](../testing/verification-log.md).

Back to the [project README](../../README.md).
