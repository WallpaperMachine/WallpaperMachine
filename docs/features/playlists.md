# Playlists

Each display can change wallpaper on its own: a rotation through a set of
wallpapers every so often, or one wallpaper by day and another by night. Nothing
changes until the user turns it on; an unconfigured display is **Off**.

## Where it lives

**Settings → Displays → a display → Playlist** holds the display's playlist.
Mirrored displays show their source and have none. **Changes on its own** picks
the mode:

| Mode | Rows | What happens |
| --- | --- | --- |
| **Off** | — | The wallpaper changes only when the user changes it. |
| **Rotate wallpapers** | **Wallpapers** (All wallpapers, Favorites, This display's list, or a local collection), **Order** (In order, Shuffle), **How often** (every 5, 10, 15 or 30 minutes, every hour, every 2, 3, 6 or 12 hours, every day) | After each interval the display moves to the next wallpaper. |
| **Day and night** | **Day wallpaper**, **Day starts at**, **Night wallpaper**, **Night starts at** | The day wallpaper takes over at the day time and the night wallpaper at the night time. |

All wallpapers and Favorites follow the library order; a list keeps the order its
wallpapers were added in. Only wallpapers that can play count, so a wallpaper that
left the library or cannot run on macOS is skipped. In order moves to the one
after the wallpaper on screen and wraps; Shuffle shows every wallpaper once, in a
new random order each round, and never picks the one on screen. A day that starts
after its night (say day 22:00, night 06:00) wraps past midnight. Times are local
clock times, so a daylight-saving day still switches at the time on the clock.

**Change now** moves a rotating display along at once and starts a fresh
interval; the row's note says roughly when the next change is due. The menu bar's
**Next Wallpaper** does the same for the panel's target display when that display
rotates, and otherwise takes the next wallpaper in library order. Both are asked
for, so they also change a display that is paused or covered; only the timer's own
changes wait (see below). When the playlist has nothing else to change to (its
only wallpaper is already on screen), Change now and a link, keyboard shortcut or
Shortcuts action asking for the next wallpaper say so instead of succeeding
without a change.

This display's list is edited from Installed: the list button in a wallpaper's
details adds it to, or removes it from, the list of the target display, and a
selection's **Add to playlist** adds every selected wallpaper. Settings lists the
wallpapers on it with **Remove**. Wallpapers moved to Trash leave every list and
every day or night choice.

### Collections and saved playlists

Installed's **Collections** sidebar creates named local groups without moving or
copying wallpaper files. Add a selection with **Add to collection…**, or toggle
membership in a wallpaper's details. A collection can feed more than one display;
membership changes are read when the next switch is chosen. Removing a wallpaper
from the library removes it from collections and saved playlists too.

Each display's Playlist disclosure has **Saved playlist** and **Save as…**.
Saving keeps a named copy of the mode, source, order, interval and day/night
choices; choosing it applies a copy to an enabled independent display. A rotating
copy becomes due immediately, but waits while that display cannot play. Manual
edits detach the display's copy from the saved plan. Renaming a plan preserves its
identity; deleting it leaves active copies and their deadlines intact. Deleting a
collection turns playlists using it into empty explicit lists, never All wallpapers.

Collections and plans have stable UUIDs; duplicate names do not merge them.
They live in the `WallpaperMachine.collections` and
`WallpaperMachine.playlistPlans` defaults. The existing per-display playlist and
next-change stores remain the source of active playback state.

## When a change happens

A change the timer brings only happens while its display is playing and
presenting. One that falls due while the user paused playback, that display is covered, the screen is locked
or the displays sleep waits, and happens once when it can play again; missed intervals are not caught up
one by one. The timer sleeps on the continuous clock, so a change that fell due
while the Mac slept happens on wake. Nothing is polled: `PlaylistScheduler` arms
one timer for the earliest change and re-evaluates when playback, presentation
(of every display together or of one display alone), the library, the playlists,
the clock or the time zone change.

Every switch runs through the display's command slot, the same one the panel's
Apply and the menu bar use, so the latest request for a display wins, and the
next wallpaper is chosen when the switch's turn comes. In Day and night, a
wallpaper the user applies by hand stays until the next half of the day, and
choosing a different day or night wallpaper applies at once. A switch that fails
is logged and not retried until the next interval or half of the day.

## Storage

`PlaylistStore` keeps every display's playlist in the `WallpaperMachine.playlists`
default (JSON; fields a newer build adds decode with defaults) and each display's
next change in `WallpaperMachine.playlistNextChange`, so a relaunch neither
restarts a long interval nor skips a change that fell due while the app was
closed. Shuffle's round is kept for the running app only.

## Code

| Part | Where |
| --- | --- |
| Model | `App/Services/Playlist/WallpaperPlaylist.swift` |
| Candidates, next pick, day and night | `App/Services/Playlist/PlaylistPlanner.swift` |
| Persistence and dates | `App/Services/Playlist/PlaylistStore.swift` |
| Timer and switching | `App/Services/Playlist/PlaylistScheduler.swift`, wired in `AppDelegate.startPlaylistScheduler` |
| Panel actions | `playlistSetting`, `playlistAdd`, `playlistRemove`, `playlistSkip` in `WebPanelActions.swift` |
| Panel | Settings → Displays in `WebUI/settings.js`; the list button and selection action in `WebUI/panel.js` |
| Collections and saved-plan actions | `WallpaperCollectionStore.swift`, `WebPanelLibraryOrganization.swift`, `WebUI/collections.js`, `WebUI/plans.js` |

## Verification

`PlaylistPlannerTests` (candidates, order, shuffle rounds, day and night
boundaries including a wrap past midnight and a daylight-saving day, decoding),
`PlaylistStoreTests` (persistence, a fresh wait after a new rhythm, removal from
every playlist, re-dating without a change), `PlaylistSchedulerTests` (a waited
interval, a change that fell due while paused happening once, day and night with
a manual choice left alone, Change now, nothing playable) and
`WebPanelPlaylistTests` (the actions' validation). Real switching on a desktop is
not covered by these tests.
