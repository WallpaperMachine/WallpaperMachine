# Automation

Three ways to drive WallpaperMachine without its window: global keyboard
shortcuts, actions in the Shortcuts app (and so Siri and Spotlight), and
`wallpapermachine://` links. All three run the same commands (`AutomationCommand`)
through `AppAutomation` into `AppDelegate.performAutomation`, which the menu bar's
**Next Wallpaper** uses too. They only do what the menu bar and the panel already
offer: play, pause, the next wallpaper, apply an installed wallpaper, open the
window. Nothing deletes, downloads or changes settings. The Focus filter, which
reacts to a Focus rather than being run, is under
[Performance → Low Power Mode, heat and Focus](performance.md#low-power-mode-heat-and-focus).

## Commands

| Command | What it does |
| --- | --- |
| Play, Pause, Play or pause | Resumes or pauses every wallpaper, as the menu bar's Play/Pause does. |
| Next wallpaper | Changes a display to its playlist's next when it rotates (see [playlists](playlists.md)), otherwise to the next playable wallpaper in library order. |
| Apply a wallpaper | Applies an installed wallpaper, named by its id (its folder name in the library). |
| Open | Brings up the control panel, on Installed, Discover, pixiv or Settings when named. |

Next and Apply act on the panel's target display unless a display is named, and
only an enabled display showing its own wallpaper can be switched. Switches share
the display's command slot with the panel, so the latest request for a display
wins. A command that arrives while the app is still starting (the system may
launch it to run one) waits up to 15 seconds for the library to load, then fails
with a message saying so. If the renderer could not start at all, opening the
panel still works, since Settings is where a failed start is put right; every
other command fails at once instead of waiting. A failure from a link or a keyboard shortcut shows at
the foot of the menu bar menu; the Shortcuts app shows its own.

## Keyboard shortcuts

**Settings → General → Keyboard shortcuts** records one shortcut each for
**Play or pause wallpapers**, **Next wallpaper** and **Open the control panel**.
None is set until recorded, so the app never takes a combination another app
expects. **Record…** takes the next key pressed in that row (Escape alone, or
moving focus away, gives up); the key must be held with ⌘, ⌥ or ⌃, except F13
to F20, which type nothing and may stand alone. The page sends the key's position
(`KeyboardEvent.code`), which `GlobalHotKeys` maps to Carbon's virtual key code,
so a shortcut stays on the same key whatever the keyboard layout. One combination
serves one action.

`GlobalHotKeys` registers them with `RegisterEventHotKey`, which works whichever
app is in front, needs no Accessibility permission and delivers only those
combinations. A combination another app already holds is refused by macOS; the
row says so, and says it again after a relaunch until it is changed. Shortcuts
are kept in the `WallpaperMachine.hotKeys` default.

## Shortcuts app, Siri and Spotlight

App Intents in `App/Services/Automation/WallpaperIntents.swift` add **Pause
Wallpapers**, **Resume Wallpapers**, **Play or Pause Wallpapers**, **Next
Wallpaper**, **Apply Wallpaper** (with the wallpaper chosen from, or searched in,
the installed ones that can play) and **Open WallpaperMachine**.
`WallpaperMachineShortcuts` offers the first three kinds to Siri and Spotlight
without building a shortcut ("Play or pause WallpaperMachine", "Next wallpaper in
WallpaperMachine", "Apply a wallpaper with WallpaperMachine"). The actions run in
the app's own process; if it is not running, macOS starts it first.

**Next Wallpaper** and **Apply Wallpaper** have an optional **Display** picker.
It lists connected, enabled independent displays using the same stable identities
as the panel; leaving it empty keeps the panel-target behavior. Execution checks
eligibility again, including when a queued command gets its turn. A disconnected
or mirrored target is rejected rather than silently redirected to another screen.

## Links

`Info.plist` claims the `wallpapermachine` scheme (`CFBundleURLTypes`). The
command is the host, and `display`, `id` and `page` are query values:

```
wallpapermachine://play
wallpapermachine://pause
wallpapermachine://toggle
wallpapermachine://next
wallpapermachine://next?display=primary
wallpapermachine://apply?id=3632513108
wallpapermachine://open?page=settings
```

A link with an unknown command, a query value the command does not take, a value
given twice, or a path is ignored and logged rather than guessed at. A browser
asks before it opens the app. **Settings → General → Shortcuts app and links**
lists the links.

## Verification

`AutomationCommandTests` (every link form, and the ones refused),
`AppAutomationTests` (waiting for the app, giving up, failures reaching the
caller), `HotKeyPreferencesTests` (nothing taken by default, persistence, one
combination per action, a refusal cleared by a change) and `GlobalHotKeysTests`
(the modifier rule and the key code, modifiers and label a press becomes). A real
press of a registered shortcut, the Shortcuts app and a link opened from a
browser need the running app and are not covered by these tests.
