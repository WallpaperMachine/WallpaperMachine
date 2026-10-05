# Audio-responsive wallpapers

Scene wallpapers with authored audio effects and web wallpapers with an audio
listener can react to sound playing on the Mac.

## Enabling it

Select the wallpaper, then turn on **General configuration -> Audio response**
in the inspector. The setting is saved per wallpaper and also applies to that
wallpaper's mirrored displays.

Capture runs only while a wallpaper with audio response on is presenting (not
paused, covered or asleep) and actually reads the sound: an audio-processing
material or particle emitter, a spectrum shader input, or a script that
registers audio buffers. A subscribed web page on screen also counts. A scene
that reads no audio, and every video wallpaper, never starts capture, even with
the setting on; the effects that would have used it received silence anyway. A
script that starts reading later starts capture then, after a short warm-up.
Capture stops when the last such wallpaper stops presenting or is removed.
Activation errors are reported rather than silently ignored.

A subscribed web page owns capture independently of renderer scene handles, so
web-only sessions work and scene cleanup does not stop their audio. Both kinds
of wallpaper share one capture tap; pause and the saved Audio response setting
still gate delivery. A web page the user paused stops asking for audio, so the
shared poller stops reading as well until it plays again. Enabling media integration alone does not enable audio response.

## Permission

macOS requests system audio recording permission at capture startup. If access
is denied, grant it in **System Settings -> Privacy & Security -> Screen &
System Audio Recording**, then retry the switch.

## What the input is

The input is sound playing in other apps. It is not the microphone, and it is
not the wallpaper's own playback. The wallpaper mute and volume controls stay
independent of audio response. Capture prefers stereo with separately analysed
left and right channels; a mono fallback supplies the same signal to both. See
[web audio response](web-wallpapers.md#audio-response) for the capture and
128-band listener contract.

## Supported effect paths

| Path | Notes |
| --- | --- |
| Shader spectrum effects | Authored audio-reactive shaders |
| Web `wallpaperRegisterAudioListener()` | 64 bands per channel, one shared delivery pump capped at 30 Hz |
| SceneScript `engine.registerAudioBuffers()` | 16, 32 and 64 bands |
| Particle emitters | Box and sphere emitters with audio frequency, bounds and exponent settings |

## Non-goals

- Pre-rendered video wallpapers do not gain reactive effects.
- The [lock-screen extension](lock-screen.md) does not capture system audio.

## Verification

Synthetic offscreen checks cover audio-driven shader color and SceneScript
scale. Device-free controller and bridge tests cover web-only capture startup,
permission, shared ownership, suspension and shutdown; offscreen WebKit tests
cover listener delivery. Live capture and desktop behavior require a separately authorized manual
check. See [Testing](../testing/README.md) and the
[verification log](../testing/verification-log.md).

Back to the [project README](../../README.md).
