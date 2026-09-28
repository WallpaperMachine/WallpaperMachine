# Power benchmarking

How to make a power claim about this project believable: the configuration
record, the counters, the condition matrix, the comparison rules a measurement
has to satisfy before it may be reported, and the measurement mode that takes
one.

Test strategy and the layers around this one: [README.md](README.md).

## Why a manifest comes first

Two runs are comparable only when the content, the real presented frame rate,
the output geometry and the machine state match. Brightness, HDR, an external
display's own panel power, charging state and thermal history all move the
result more than most renderer changes do. `python3 scripts/power_benchmark.py`
writes that configuration to `artifacts/power/manifest-<timestamp>.json`:
commit and whether the tree was dirty, build configuration, chip and memory,
macOS build, every online display's pixel geometry and refresh rate, charging
and low-power state, recorded thermal warnings, the Homebrew library versions
actually linked, and the pinned `upstream/` revisions.

Without `--measure` the script measures nothing. Every condition is written as
`"measured": false`, and `measurement_tool` stays `null`. `--print-only` emits
the document without writing an artifact.

## Measuring a window

`--measure SECONDS --condition ID` samples the processes a condition is about
and the machine as a whole before and after a window of that length and writes
`artifacts/power/measure-<timestamp>.json`: the manifest, `"measured": true`,
the sources in `measurement_tool`, the condition marked measured, and
`measurement` with the actual elapsed time, one row per role, the coalition
energy, the system power and the package power. One line per role is printed,
e.g. `app: CPU 38.2 %, GPU 65.1 %; coalition CPU 67 mW, GPU 5434 mW`, then the
total over all coalitions. The window is always the length asked for: a
powermetrics that fails or is refused at once does not shorten it.

| Role | Executable | Note |
|---|---|---|
| `app` | `WallpaperMachine` | |
| `window_server` | `WindowServer` | Composites every window, the wallpaper included |
| `core_audio` | `coreaudiod` | Runs the system audio tap an audio-reactive wallpaper asks for |
| `web_content` | `com.apple.WebKit.WebContent` | Every such process of this user, not only this app's |
| `extension` | `WallpaperMachineExtension` | Lock-screen extension, when running |

- **CPU %** is the growth of `ps -o time` (user + system) over the window.
- **GPU %** is the growth of `accumulatedGPUTime` summed over the process's
  `AGXDeviceUserClient` entries in `ioreg`: how long its command queues kept the
  GPU busy. It is utilisation, not energy. A process whose GPU client closed
  during the window reports no GPU value instead of an undercount.
- **Coalition energy** is the CPU and GPU energy the kernel charged to each
  role's resource coalition over the window, in mW, plus the total over every
  coalition, read without privileges the way the app's own Energy use readout
  reads it (`coalition_info_resource_usage`; see
  [performance](../features/performance.md#energy-use)). It is the figure to
  compare WindowServer by: its coalition is its own, while `ps` CPU time says
  nothing about energy. The app's coalition includes its XPC services and every
  WebContent process it started, so the `web_content` row counts only other
  coalitions. GPU energy is the whole GPU's energy shared out by GPU time, so
  when other coalitions keep the GPU busy for 25 % of the window or more the
  window is marked contended and the app's figure reads high.
- **System power** is the whole machine's mean draw over the window, from the
  battery controller's own running sums in `ioreg -r -c AppleSmartBattery -a`
  (`PowerTelemetryData`): `AccumulatedSystemLoad` over
  `SystemLoadAccumulatorCount` for what the machine consumes on either power
  source, and the `SystemPowerIn` pair for what the adapter delivers, charging
  included, when there is one. It needs no privileges, it is what a menu-bar
  watt meter shows, and it is the only figure here that includes memory, the
  display and everything else outside the CPU and GPU cores. It includes every
  other application too, so it is only ever compared against a paired baseline.
- **Package power**, with `--powermetrics`, is the mean of every
  `powermetrics --samplers cpu_power,gpu_power -i 1000 -n SECONDS` sample:
  CPU, GPU, ANE and combined mW. powermetrics needs root. The script runs it
  directly when it is root; with `--sudo-password-stdin` it reads one line from
  stdin and passes it to `sudo -S` on stdin only — never in arguments, the
  environment, the output or the artifact; otherwise it tries `sudo -n`. A
  refusal is recorded as `package_power.measured = false` with sudo's reason,
  and the other rows are still written.

A desktop run is taken serially, with the display set and power source
unchanged across a comparison: quit the app with an Apple Event and wait until it
has exited (`open` can fail with `-600` for a few seconds after that), launch
with `open --env WALLPAPER_MACHINE_DIAGNOSTICS=60 --env
WALLPAPER_MACHINE_DIAGNOSTICS_DELAY=120`, and start a 60-second measurement 120
seconds after launch. These independently started windows approximately overlap;
the delay alone does not synchronize their boundaries. The diagnostics report's
`window elapsed_ms` gives its own measured duration, and `draws_executed` divided
by that duration is diagnostic-window draw throughput, not displayed FPS. A
same-throughput power claim needs timestamped counter deltas aligned to the
actual power window. Neither the configured ceiling nor timer-wakeup counts
provide elapsed time or displayed-frame counts.

Before 2026-09-28 the frame clock delivered 45–52 draws/s at a configured 60 fps
ceiling. `ThreadTimer` computed each deadline from the time the previous tick
actually woke, not from the previous deadline, so every wait's timer slack was
added to the period instead of being absorbed: a headless probe with a
zero-cost draw measured about 20.3 ms between ticks at a 60 fps ceiling
(50.5 draws/s), about 10.4 ms at 120 (100/s) and about 37.5 ms at 30 (27/s). A
cadence tick is now anchored to the deadline it was due at, and one more than a
whole interval late restarts the cadence instead of bursting to catch up
(`ThreadTimerTest.CadenceKeepsItsPeriodDespiteWakeSlack`: 50 ticks in 600 ms
at 10 ms before, 54–62 required after). Measurements taken before that date at
a given ceiling therefore describe fewer frames than the same ceiling delivers
now. `FrameTimer` still drops any tick that finds the
previous DRAW still running, and on Compatibility a DRAW includes the GPU frame
(the fence wait follows the present). A DRAW that ends within a quarter
interval of the tick it made the clock drop runs that frame at once and restarts
the cadence from it (`FrameTimerTest.ADrawSlightlyLongerThanTheIntervalDoesNotHalveTheRate`:
18 ms draws at 60 fps deliver at least 42 frames a second, 35 without it); one
that ends later loses the whole period, so a scene that cannot keep up settles at
a steady fraction of the rate instead of drawing back to back. Otherwise
`FrameEnd` re-arms the clock only for an outstanding update request. This is
measured delivery, not presentation: whether and when those frames were
displayed is still not observable. Correcting the cadence raised delivered work
toward the configured ceiling, so a comparison across that change has to report
its throughput separately from any power figure. The app opens its
control panel at launch, so each such run includes it; while the library page
is visible, installed GIF previews animate. Some runs showed WebContent at
8–13 % CPU and higher WindowServer CPU, but the recordings did not establish
that preview animation caused the difference. With other applications running, system power with the
app quit ranged from 10 W to 25 W over one morning and package power moved by
about 1 W between repeats; the app's own CPU and GPU percentages were the
steadier signal, and system power needs a baseline taken minutes from the run it
is set against.

## App-process CPU and memory comparisons

For an app-level comparison, identify the exact executable PID and sum only its
resource coalition (the app and its XPC/WebKit helpers), not every WebContent
process on the machine. Reject windows containing another WallpaperMachine
instance or a change in the tested presentation state. A closed-panel sample
must remain without an on-screen panel throughout; it is not a playback test.

`proc_pid_rusage` supplies resident bytes and physical-footprint bytes. Report
these separately: adding process RSS can double-count shared pages, while
physical footprint is the kernel's memory charge, not free system RAM. Normalize
its Mach-absolute CPU counters with `mach_timebase_info` and cross-check totals
against `ps -o time`; assuming nanoseconds directly undercounted this Apple
Silicon machine by 125/3. CPU percentages use one logical core as 100%.

Record window lengths, warm-up, content/cache identity, and per-build ranges.
Several windows from one app session are not independent launch repetitions.
Live Workshop prefetch can change even if the displayed page matches; disclose
that difference and avoid generalizing a single browsing comparison to playback
or claiming a CPU improvement when the observed ranges overlap.

## Per-app energy without root

Findings from 2026-09 on an M5 Pro, macOS 26.6, checked against `powermetrics`:

- `proc_pid_rusage` `ri_energy_nj` tracks CPU energy (within 8 % of the
  `powermetrics` CPU delta for one busy core) but includes no GPU energy.
  `task_power_info_v2.task_gpu_utilisation` is only accumulated on x86_64 and
  reads 0 on Apple Silicon.
- `accumulatedGPUTime` in `ioreg` `AGXDeviceUserClient`, which this script
  reports as GPU %, gave 2.8–38.6 % for five runs of the same saturating load.
  Treat it as a coarse activity signal, never as energy.
- Resource-coalition accounting (`coalition_info_resource_usage`: `energy`,
  `gpu_energy_nj`, `gpu_time`) needs no privileges, covers the app with its
  WebKit and decoder services, and summed over all coalitions matches the
  whole-GPU figure within 5–9 %. GPU energy is apportioned by GPU time, so it
  overstates an app sharing the GPU with a heavy load. The in-app readout uses
  it; see [features/performance.md](../features/performance.md#energy-use).

## WindowServer's share

Findings from 2026-09-28 on an M3 Max, macOS 27.2, built-in XDR at 120 Hz in
a 4112x2658 scaled mode, AC power, coalition energy over 40–45 s windows run
in alternation, other apps hidden. The probe was a disposable desktop-level
window configured like `MWEWallpaperDesktopWindow` whose frames are one clear,
so its own GPU work was negligible.

- **It follows the present rate of a full-screen layer.** With the desktop
  exposed, WindowServer drew 31–39 mW idle and, for the probe, 197–213 mW at
  30 fps, 294–364 mW at 60 and 568–571 mW at 120. Lucy (3521337568) cost it
  the same for the same rate (506 mW at about 89 fps, 297–361 mW at 46–50).
  Next to the app's own GPU work (about 5 W at 89 fps, 2.3 W at 48, 1.1 W at
  26) it is about a tenth, so the renderer's frame rate is the lever for both.
- **A covered desktop still costs it.** Behind zoomed windows the strip under
  the translucent menu bar kept the wallpaper presenting; pausing that display
  took WindowServer from 365 to 23 mW (the covered-desktop setting in
  [performance](../features/performance.md#playback)).
- **No direct-to-display.** Metal System Trace's `displayed-surfaces-interval`
  table never marked a wallpaper frame `direct-to-display` in any drawable size
  or colour space: a desktop-level layer under the Finder desktop window and
  the menu bar is always composited.
- **Pacing and drawable size did not matter.** At 60 fps, plain presents,
  `presentDrawable:afterMinimumDuration:` and a `CAMetalDisplayLink` gave
  294–377 mW; a drawable at the panel's 3456x2234 or half the backing size
  gave 287–388 mW against 294–364 for the backing size.
- **Colour space costs the probe a third, the wallpaper little.** The layer
  is tagged sRGB so it matches the sRGB desktop poster, and WindowServer
  colour-matches it to the display. In strict alternation the probe cost
  268–290 mW tagged sRGB against 175–200 mW tagged with the display's own
  space at 60 fps, and 495–503 against 328–345 at 120. Lucy at 60 fps, tagged
  or left untagged, gave 215–333 against 203–307 mW (pairs 12, 75 and 19 mW
  apart), inside the run-to-run spread. Not adopted: an exact sRGB-to-display
  conversion in both renderers, a poster that stays sRGB and a rebuild on
  every display-profile change would buy at most tens of milliwatts next to
  about 3 W of rendering.
- **Not established:** whether the ProMotion panel drops below 120 Hz for a
  60 fps wallpaper. Single 6-second traces disagreed (display link 78 Hz at
  60 fps but 121 Hz at 30), and about 30 composited frames a second had no
  attributed process even with nothing running. Panel power is outside
  coalition energy and `powermetrics`, and battery-telemetry system power was
  too noisy to settle it.

Two traps: a covered-layout run with the user active gave an idle WindowServer
of 141–762 mW, so compare only quiet windows; and Chrome left open triggered
about 60 composites a second on its own.

## Runtime counters

Two counter surfaces answer two different questions, and a power claim needs
both. A suspend decision recorded on one side proves nothing about the work on
the other.

`Shared/RuntimeCounters.swift` holds the in-process counters for what the
application decided and what the web host did. They are **off by default**:
`record` does nothing outside a session opened with `startSession(duration:)`,
and the session expires on its own so a forgotten switch cannot keep counting.
Counts are per surface — `RuntimeSurfaceKey(kind:displayID:generation:)`, where
the generation separates two surfaces that reused one display id across a
hot-plug or wallpaper switch — and the surface table is bounded at
`RuntimeCounters.maximumTrackedSurfaces`, reporting `droppedSurfaceEvents`
rather than growing without limit.

The renderer counts its own work: the frame clock's wakeups and draw requests,
draws executed and dropped, queue submissions, present requests, frame-fence
completions, simulation ticks, frames left undrawn because they would have
repeated the picture on screen (`presents_skipped_unchanged`), the effective
pause reasons as independent bits,
and the decoder's outputs, seeks, selected/reused/skipped frames, conversions
and imports. Those are also **off by default** — one relaxed atomic load gates
each increment — and reading them is a pull: nothing is pushed to the UI, logged
per frame or written to disk, and enabling starts no thread and no timer.

The two groups inside a renderer row are deliberately separate.
`timer_wakeups` through `presents_skipped_unchanged` are work a surface performs alone and
must stop when nobody can see it. The `video_*` values describe the decoded
source, which may legitimately keep running while one of its consumers is
hidden, provided another consumer still presents it. Collapsing them would make
a correctly suspended surface look busy.

`RuntimeDiagnosticsSession` opens both halves for a bounded window and produces
one aggregated report, headed by how long the window actually ran
(`window elapsed_ms=`), measured rather than assumed. The application starts
one when `WALLPAPER_MACHINE_DIAGNOSTICS=<seconds>` is set in the environment,
`WALLPAPER_MACHINE_DIAGNOSTICS_DELAY=<seconds>` after launch when that is set
too; a value that is not whole seconds starts nothing. Without the first
variable nothing is started, nothing counts and no timer exists.

The counters exist to answer one question per condition: did the work for a
surface nobody can see actually stop? A count that keeps rising for an occluded
surface falsifies the change regardless of what a CPU graph shows.

### What the platform cannot report

`present_requests` counts requests to present. Whether the compositor ever put
a frame on a display is a different measurement, and this backend — MoltenVK
over a `CAMetalLayer` swapchain — has no presentation-feedback source for it.
The report says `presented_frames=unavailable`; the request count is never
relabelled as displayed frames, and no frame-rate claim may be derived from it.

### A/B comparison entry points

Three switches make a comparison measure one change in one binary rather than
two builds. All cover a strategy only: none restores a resource-lifetime or
decode-correctness defect.

| Switch | Off (default) | On |
|---|---|---|
| `WALLPAPER_MACHINE_CONTENT_PACING=1` | Tick at the configured ceiling | Pace video to its observed content rate |
| `WALLPAPER_MACHINE_FEEDBACK_COPIES=1` | Native Metal trades textures for a copy a layer only makes to read the image it draws into | Every such copy is made as a copy; the picture is byte-identical either way |
| `experimental.native_video_backend` in the app config | Every wallpaper on the scene engine | Eligible plain local videos on the platform player |

Demand-driven pacing is off by default because its remaining exposure cannot be
bounded here: the content period only reaches the frame clock after a completed
frame, so a rate that turns out tighter than the interval being waited out loses
every frame produced during the remainder of it. The native video backend is off
by default because it has never been visually verified and supports a declared
subset only.

A four-way attribution therefore needs: the baseline; baseline plus R02;
baseline plus I01; and the native backend opted in. R02 and I01 are not switched
— they are correctness and resource changes, so comparing them needs a separate
build directory or worktree. Whichever way two versions are compared, they need
isolated `WALLPAPER_MACHINE_HOME` directories and must be measured serially,
never concurrently.

### What the native backend cannot report

Decode and present counts inside AVFoundation are not observable from outside
the framework, so they are reported as unavailable rather than invented.
`AVPlayerLooper` keeps more than one copy of its template item queued to make
the loop seam gapless, so the queued-item count is reported as the system gives
it and is never claimed to be one with no pre-buffering.

## Condition matrix

| ID | Condition | What it separates |
|---|---|---|
| B0 | Application quit, system static wallpaper | System and display noise floor |
| B1 | Application running, no active wallpaper, panel closed | Host baseline cost |
| B2 | Same content, static poster only | Animation cost versus image and compositing cost |
| T1 | Single display, static or low-frequency scene | Idle ticks and dirty propagation |
| T2 | 1080p/4K/ultrawide video at 24/30/60 FPS | Decode, conversion, frame rate, pool budget |
| T3 | Simple, multi-layer post-processed, particle and video-texture scenes | CPU versus GPU versus bandwidth |
| T4 | Web wallpaper with and without a cooperating pause listener | Whether host-side suspension is real |
| T5 | Two displays, one visible one occluded, then both occluded | Per-surface policy and shared consumers |
| T6 | Lock screen, unlock, display sleep, system preview | Joint app/extension presentation ownership |
| T7 | Rapid wallpaper switching, hot-plug, window and resolution changes | Reclaim, recovery, leaks |
| T8 | Broken input, unsupported format, repeated web crashes | Whether error paths keep burning power |

Wallpaper material comes from the local corpus
([wallpaper-corpus.md](wallpaper-corpus.md)) or synthetic fixtures. Copyrighted
Workshop assets are never committed.

## Comparison rules

```text
incremental average power = condition average - paired baseline average
incremental energy        = ∫(condition power - paired baseline power) dt
saving                    = (old incremental - new incremental) / old incremental
```

- Compare equal content, equal output geometry, equal **real presented** frame
  rate, equal scaling and equal color contract. A change that lowers frame rate,
  resolution, animation speed or effect count is a quality tier, not an
  equal-quality saving, and must be reported as such.
- Observe the application, any renderer helper, `WebContent` and the lock-screen
  extension **and** `WindowServer`. The main process alone proves nothing.
- Report absolute differences and spread. When the old incremental power is at
  or below the noise floor, do not report a percentage.
- Warm shaders, caches and temperature first; report cold start, first decoded
  frame and first shader compile separately from the steady-state window.
- Activity Monitor's Energy Impact is not watts, and GPU utilization is not
  energy.

## Authorization boundary

Without `--powermetrics`, `scripts/power_benchmark.py` is safe to run: it reads
configuration and the counters of processes that are already running, and
changes nothing. Everything else that produces an actual power number is out of
scope for routine verification and needs explicit authorization, because it
requires controlling the desktop, changing the user's wallpaper, or elevated
sampling:

- `powermetrics` (root), Instruments/`xctrace`, Power Profiler, external meters.
- Setting a wallpaper, unlocking or locking the session, or driving Spaces.
- Screen capture and audio capture.

Until then, a power result is recorded as unverified, never as a pass. The
boundary itself is described in
[../development-tools.md](../development-tools.md).
