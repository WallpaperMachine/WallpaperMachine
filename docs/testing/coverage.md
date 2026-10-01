# Current native coverage

What the Swift test bundle actually asserts, domain by domain. This is the
inventory behind `python3 scripts/test.py`; the strategy, layers, tiers and
evidence policy live in [README.md](README.md).

Read it to find out whether a behavior is already covered before adding a test,
and to see the exact limits of a claim — several entries end by naming what the
covered case does *not* establish. Nothing here starts the app, opens a window
or touches the desktop.

Swift tests cover, without starting the app:

- **Library** — complete atomic adoption, concurrent destinations, duplicates,
  cancellation, and rejection of linked, special, or incomplete content;
  deletion; scene-asset installation. `ImageImportTests` imports real ImageIO
  pictures: the still `web` project, the original's bytes kept, the file name
  kept out of the page, the fit chosen from the shape, a JPEG display copy for a
  TIFF, an undecodable file refused, **Keep both** keeping the `image-` prefix,
  and `LibraryImportStore` refusing a second import and rescanning once.
  `WallpaperImportPickerTests` exercises real child processes: cancellation
  before launch, reaping after cancellation, cleanup when activation fails,
  invalid handshakes, and failed exits not being treated as user cancellation.
  Native picker localization and the real selection-to-parent URL handoff
  require a separately authorized desktop smoke; these tests open no picker.
  The Finder/Dock hand-off in `AppDelegate` is not covered (it needs a running app).
  Collections and named plans cover stable identity, ordered membership, cleanup,
  detach-on-edit and paused/replaced queued transitions. `WallpaperPresetStoreTests`
  covers typed applied-property snapshots, portable managed attachments, limits,
  hidden file exclusion, alias rejection, draft/permission rollback and
  applied-source retention after deleting a preset. `WallpaperBackupTests` exercises real package export,
  preview, staged next-launch restore, conflict policy, parser/schema rejection,
  authorization, plain-text preservation, rollback and interrupted recovery,
  persistent-only preferences, full-size preset archives and manifest preflight.
  Image placement tests cover fit-aware geometry, per-display persistence,
  version-bound single-flight upgrade, actual resource changes and reset races;
  `StillImagePageRenderingTests` exercises the generated page offscreen.
  Compatibility checks cover target/content/config generations and truthful
  unknown states, not complete scene or on-screen compatibility.
- **Workshop** — search and pagination beneath the UI, committed-query
  pagination, window-sized pages cut from cached Steam pages (including a size
  change while a page loads), superseded requests, cancellation, and exact
  failed-request retry through the real page parser. Two `testLive…` cases fetch
  Steam's real pages and are opt-in
  (`WALLPAPER_MACHINE_NETWORK_TESTS=1`, see
  [README.md](README.md#opt-in-layers)); the page format itself stays covered
  offline through `decodePage` against recorded markup. Thumbnail cache: CDN scaling only for Steam image
  hosts, still-frame JPEG extraction from animated previews (skipping a black
  fade-in, keeping frame 0 for bright, uniformly dark or still sources), one download per
  URL under concurrent requests, disk hits across instances, fallback when the
  CDN refuses scaling, no cache entry after a failed fetch, the concurrency cap
  and oldest-first pruning; the animated relay returns Steam's bytes on its own
  lane and refuses single-frame sources without a request; the scheme handler
  refuses thumbnail and animated ids it has not announced. An offscreen WebKit
  regression (`ControlPanelDiscoverTests`) checks that Discover tiles load the
  still first, admit the animation beneath it, fade the still out only for a
  bright animation and never for a black one, and skip single-frame previews.
  Updates: `WorkshopTests` decodes a recorded details answer (served item,
  withdrawn item, another app's) and checks the request form;
  `WorkshopUpdateStoreTests` covers what counts as outdated, recorded downloads
  against `project.json` dates, non-Workshop ids never sent, results kept across
  a relaunch, a download making an item current, the daily limit and its switch,
  a failed check keeping what was known, and forgetting deleted items;
  `ImportTests` covers the swap that replaces an installed tree. The reload of a
  wallpaper on screen after its update needs a renderer and is not covered.
  Other sources: `WorkshopSourceTests` covers reading Steam's session cookie,
  author pages (ids, total, name, and only Steam's sign-in page meaning signed
  out), a collection's order, collections marked on browse pages over a
  megabyte, the sidebar's rules on unfiltered pages, the age-rating sampling of
  collections, a collection's pages, every page of subscriptions sent with the
  session, and the store's back history, sign-in, a session Steam ended and
  sign-out, all against a fixture protocol. `WebPanelWorkshopSourceTests`
  covers the panel's source actions, their validation, sign-in through an
  injected window and refusing to download a collection. Steam's real sign-in
  window is not covered.
- **Pixiv** — decoding of pixiv's ranking, search, page-list, status and
  profile answers (numbers sent as strings, content types as objects or lists,
  withheld and members-only entries), ratings including R-18 and R-18G, search
  and ranking addresses, query sanitising without a sign-in, request pacing,
  the session cookie reaching `https://www.pixiv.net` only, sign-in, log out,
  a keychain refusal, and a saved session that pixiv's status reports as signed out
  (at launch, and after an R-18 ranking is refused) against an in-memory store, the
  download queue (concurrency, cancel, retry, shutdown) and packaging (sniffed
  formats, scaled display copies, kept copies, staging reclaim).
  `WebPanelPixivTests` checks the actions' validation and snapshot without a web
  view, and the offscreen `ControlPanelPixivTests` drives the tab through the
  real page with the sign-in window replaced by a closure. None of it reaches
  pixiv: its signed-in answers and the real sign-in page are not covered.
- **Downloads** — private terminals per job, transfers side by side up to the
  slot limit once the first job's sign-in is accepted and saved (siblings start
  silently while it still transfers), the queue waiting behind a job that is
  still authenticating or renewing a stale sign-in, serial order without a
  saved sign-in, a Steam "logged in elsewhere" kick re-queuing the ended job
  and turning the queue serial, the downloads-at-once ceiling changing mid-queue
  (raising starts waiting jobs, lowering never stops a running one), persisting
  across relaunch clamped to 1–6 and reaching Swift from the Settings select as a
  number, per-job secrets,
  saved-sign-in handoff to the next job, cancellation, duplicate-click
  suppression, FIFO handoff after failure/cancel, shutdown without launching
  queued work, staging reclaim limited to directories nothing is writing to,
  protection against stale credential rejections erasing a newer session,
  retained-intent setup/account progression, explicit shared-resource consent
  including reinstall, resource-job deduplication, account correction, removal
  preventing resumption, sign-in ownership checks (owned, missing, unconfirmed,
  split output and switching accounts), and download-speed sampling (see
  [renderer.md](renderer.md) for the `nettop` streaming detail). The
  downloader suites share `DownloaderTestCase` (`Tests/Unit/Workshop/`) and
  split by concern: `DownloaderLifecycleTests`, `DownloaderSessionTests`,
  `DownloadQueueTests`, `SteamCMDRuntimeValidationTests` and
  `DownloadTelemetryTests`.
- **Steam runtime** — SteamCMD setup against isolated preferences/directories,
  `URLProtocol` archives, real system `tar`, and owned child processes:
  publication/replacement, invalid discovery, traversal/link/archive-size
  boundaries, strict package manifests, both checksums, HTTP encoded/decoded
  lengths, duplicate package paths, real zip backslash normalization, execute
  permissions, manifest retention, monotonic progress, network failures (including
  preserving a rejected redirect's original diagnostic when its final response
  arrives before cancellation), signature-policy blocking, cancellation, and no
  late writes. Runtime fixtures
  require arm64, reject Intel-only copies and retire old bootstrap candidates;
  they exercise canonical macOS path aliases and nested Mach-O executable
  dependencies. Approval tests use isolated fixtures only: exact SHA-256
  receipts, signature/policy-failure rejection, stale candidates, changed
  resources, private copies, quarantine scope, same-path retry/relaunch, and
  explicit discard. An installation-to-downloader regression launches the
  published executable through the real PTY downloader and asserts imported
  manifest and media bytes. Fixtures do not prove that Valve's current
  distribution passes this Mac's policy; the opt-in `SteamCMDLiveInstallTests`
  checks that separately using a temporary native package install and no-login
  smoke run (see [README.md](README.md#opt-in-layers)).
- **GitHub updates** — fixture JSON, a fake client and isolated URLSession
  responses: version comparison, disk-image asset selection, host allowlisting,
  progress clamping, classified errors and install retry/timeout. A missing latest
  release is normal only after the repository is confirmed reachable; missing
  repositories, failed lookups and malformed metadata remain errors. Rechecking
  clears stale release notes/availability and can discover a later release. The
  offscreen About flow also checks again from the no-release state before
  downloading a fixture update. The installer is exercised against real disk
  images made with `hdiutil`: the app is copied out without following the
  `Applications` link, a foreign bundle is refused, and the image is detached
  either way; an app that cannot install in place opens the downloaded image. These
  tests never contact GitHub, download a real release, or replace the running app.
- **Panel** — the offscreen `WKWebView` suites share `ControlPanelTestCase`
  (`Tests/Unit/Panel/`) and split by page: `ControlPanelShellTests` (window,
  language, appearance, About/update, top bar), `ControlPanelLibraryTests`
  (sorting, tile marks, filter sidebar, download setup, error dismissal),
  `ControlPanelDiscoverTests` (pagination, grid, download rings, previews) and
  `ControlPanelSyncTests` (hidden-panel pushes, option fetches, display titles).
  Offscreen `NSHostingController` layout proposals at 760×560,
  960×640, and 1240×800 in every shipped language, asserting the root accepts each
  window width without forcing a taller window; an offscreen `WKWebView`
  regression that loads the bundled interface under its custom scheme, waits for
  the native reply bridge, routes a `navigate` message to Settings, and rejects
  a non-allowlisted external URL; a regression in every shipped language that
  checks the injected language, rendered navigation/accessibility labels, settings
  and result summary, plus locale fallback and literal placeholder substitution;
  a language-switch regression that sends `languageSetting` and confirms the
  page re-renders in place, the picker offers every shipped language under its
  own name, and an unshipped tag is refused. Panel tests that read rendered
  labels must pass `appLanguage: .english()` (`Tests/Unit/Support/TestAppLanguage.swift`)
  or a store built with explicit `systemLanguages`: the default
  `AppLanguageStore.shared` follows the developer's in-app language choice, so an
  implicit store renders another language on a Mac where the app was switched to
  one and English-wording assertions fail. `Tests/Unit/Localization/` covers
  the preference store: system matching, persistence, the `AppleLanguages`
  mirror and rejected tags. Python catalog checks
  (`scripts/tests/test_panel_localization.py`) require the Swift registry, the
  `i18n.js` registry, `WebUI/locales/` and both `.xcstrings` to name the same
  languages, every native key to be translated, every catalog to hold the same
  keys, and reject duplicate/empty entries, missing direct-call and
  static-markup translations, and placeholder mismatches; an About-updates regression that checks,
  downloads, and refuses to install without a window, plus a snapshot mapping of
  idle/available/ready actions; a `dismissError` regression where a
  library-refresh failure and a download failure raised through the real
  download path are reported once, stay suppressed after dismissal, and surface
  again when the same failure recurs after a successful refresh; and a hidden
  download fixture that observes password-prompt/downloading transitions.
  Editor-state tests cover locale-specific scaling, invalid raw text, and
  independent wallpaper/field drafts.
  Refinement regressions cover secondary-only global playback and the no-assignment
  state; 760px settings containment with long native select options and reports;
  active numeric/search drafts, caret, disclosure and scroll preservation;
  theme changes without renderer settings and explicit lock-screen unavailability;
  onboarding background focus isolation and Steam prompt focus transitions;
  ownership notices, continuing without ownership, and rechecking after purchase;
  revealed-password retention without a value attribute or HTML echo, followed
  by submit clearing through the fake Steam runtime; and real native rejection
  of an anonymous download account with modal feedback, retained intent and
  late-error isolation after reopening. Non-onboarding page scenarios finish the
  visible welcome flow first. These checks remain windowless; they do not prove
  desktop presentation or animation smoothness.
  `ControlPanelWindowSizingTests` also exercises the native chrome offscreen at
  full-screen, half-screen and minimum panel sizes: navigation hit-testing below
  an opaque title bar, unobscured content bounds, and restoration of the windowed
  title-bar layout without resizing the frame. It does not enter a full-screen
  Space or verify the live Split View transition.
  `ControlPanelBackupFlowTests` drives real controls and isolated package writes,
  preserving the library-inclusion and replace-conflict choices and checking that
  staging/cancellation leave running files untouched. It opens no file panels.
- **Appearance** — preference recreation, rejection of invalid changes without
  overwriting saved values, recovery from a damaged saved accent, reset
  isolation, plus an offscreen appearance regression that commits the real
  Appearance controls through the native bridge, changes accent/tone, resets,
  simulates live native appearance changes on a detached view, verifies explicit
  Light wins over Dark, and reloads through the WebContent recovery path with
  saved customizations intact.
- **Desktop posters** — synthetic renderer pixels and an in-memory workspace:
  lossless PNG dimensions/channel order/orientation, malformed frames,
  synchronous frame requests (no Apply debounce), first-frame delivery to all
  Spaces without a Space-change event, stale old-layer completion, automatic
  retry, independent display/Space originals, duplicate-frame suppression,
  immutable frame URLs with reference-aware cleanup, bounded retention of the
  newest posters on a current-Space-fallback display and on one with an
  unreadable Space (whose failure is still reported), a Space change that
  re-applies the existing poster without capturing a new one while a surface
  without a poster still requests it, legacy journal migration,
  relaunch recovery, external wallpaper changes, and write failures. Topology
  and native option/path translation use fixtures, including empty
  inherited/default native selections, rejected native acknowledgements, and
  unreadable-original errors. Empty per-Space selections resolve through the
  public API before any poster write, preserving independent display originals
  even when a write also changes inherited defaults. If no original resolves,
  synchronization refuses to replace the system wallpaper. A legacy empty
  journal reports failed restoration and can be repaired from a real original
  even when the frame is unchanged; relaunch then restores that original.
  Per-Space originals still take precedence over public-API fallbacks, and
  external user choices survive restoration. Coordinator tests use unattached
  `CAMetalLayer`s and injected notification/encoding services. Shutdown fixtures
  simulate a native provider reload whose persisted PNG is temporarily invisible
  to the legacy API, delayed persistence after setting the original, permanent
  write failure followed by retry, and an external user choice during the wait.
  Native-store reference fixtures cover display/Space scope, inherited fallbacks,
  linked Desktop choices, and exclusion of Idle and inactive fields.
- **Playback conditions** — `SystemConditionMonitorTests` with injected Low Power
  Mode and thermal readings and a private notification center: Low Power Mode
  acting only once an action is chosen, only serious and critical heat counting
  (and staying hot not re-announcing), a Focus filter joining the other
  conditions, its state surviving a new instance, and `stop()` releasing every
  action. `WallpaperFocusFilterTests` pins the filter's default to the choice
  that lets wallpapers run, since macOS performs it with defaults when a Focus
  ends. The real Focus Settings pane and a real Low Power Mode are not exercised.
- **Automation** — `AutomationCommandTests`, `AppAutomationTests`,
  `HotKeyPreferencesTests` and `GlobalHotKeysTests`; what each covers, and what
  needs the running app, is in [automation](../features/automation.md#verification).
- **Playlists** — `PlaylistPlannerTests`, `PlaylistStoreTests`,
  `PlaylistSchedulerTests` (fake clock, library and activation; no renderer) and
  `WebPanelPlaylistTests`; what each covers is listed in
  [playlists](../features/playlists.md#verification).
- **Lock screen** — per-display ownership, independent originals, external
  Desktop changes, journal recovery after service-reload failure, inherited
  Space cleanup, system-copied fallback restoration, global linked conflicts,
  removal and recovery of global Desktop/Idle overrides, independent activation
  from macOS's linked default (both inherited and explicit per-display choices),
  exact linked restoration after disable or reload failure, preservation of
  later global Desktop/Idle edits, complete Desktop/Idle fields in synthesized
  display and Space overrides when either mode runs alone, and removal of those
  overrides on recovery while preserving external edits, rejection of malformed
  linked/inherited baselines without store writes, journal loss or service reload,
  and a poster-handoff regression covering a pathless original, retention of its
  poster and recovery journal, and rejection of delayed encoding completions
  after suspension. `WallpaperPresentationAuthorityTests` covers both display/
  host wake orders and preserves user pause across sleep/wake.
  `LockScreenFrameBackingTests` composites real snapshot pixels under a Metal
  layer without a drawable and checks snapshot ownership across replacement.
  `LockScreenWallpaperServiceTests.testDisplayTopologyChangesDoNotClearSurvivingLockScreens`
  records every published manifest for synthetic display IDs through disconnect,
  reconnect and primary ordering changes, then checks that explicit disable
  still clears all scenes. It does not depend on a second physical monitor.
  Service regressions also restore both saved requests without a lock-screen
  acknowledgement, retain only the screen-saver selection, propagate pause changes
  without automatic lock-screen retries, and recover on explicit retry. They cover
  screen-saver disable/re-enable (including Off during a lock-screen retry before a
  missing display UUID returns), stale readiness rejection, current renderer failure,
  and full rollback when the shared extension or Idle-only publication fails.
  These tests do not establish real lock-screen visual timing or private XPC
  snapshot transport. No test selects a real wallpaper.
- **Diagnostics** — `AppLogRouterTests`: lines logged before the bridge keep
  their time and order and are written when it attaches, overflow is reported
  rather than silent, loads start only once the log is open, and concurrent
  lines all arrive. `DiagnosticsRedactorTests`: home paths in all forms, user
  and account names as whole tokens only, SteamCMD sign-in names, and
  credential values without touching `token expired`. `DiagnosticsBundleTests`:
  newest sessions first including `-N` suffix order, the byte budget with tail
  truncation, crash-report prefix, age and count filters, a missing extension
  log noted, and the zip's actual entries. Log line format, retention and the
  verbose setting are covered in Rust (see
  [diagnostics.md](../features/diagnostics.md#verification)).

What native tests do **not** establish: macOS acceptance/restoration of native
wallpaper selections, live GitHub release install and Applications replacement,
how Finder draws the disk-image window, Steam CDN throughput, live-account session reuse,
Mission Control cache refresh, and any visual timing. Those stay on
[manual-smoke.md](manual-smoke.md).
