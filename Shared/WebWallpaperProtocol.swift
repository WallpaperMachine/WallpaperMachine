import Foundation

/// Wallpaper Engine author protocol, shared by desktop and native saver web content.
enum WebWallpaperProtocol {
    /// Resolves a project-relative entry file to the path identity used for
    /// comparison, or nil when it leaves the project folder once symlinks are
    /// resolved. Comparing only the last path component instead makes a nested
    /// entry such as `sub/index.html` never equal to itself, which rebuilds the
    /// page on every reconcile.
    static func canonicalEntryURL(projectURL: URL, entryFile: String) -> URL? {
        // A manifest entry is always relative to its project. An absolute path
        // would otherwise be appended as a component and silently resolve to a
        // file inside the project that the author never named.
        guard !entryFile.isEmpty, !entryFile.hasPrefix("/") else { return nil }
        let root = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        let entry = projectURL.appendingPathComponent(entryFile)
            .standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        guard entry.pathComponents.count > rootComponents.count,
              Array(entry.pathComponents.prefix(rootComponents.count)) == rootComponents
        else { return nil }
        return entry
    }
    /// Name of the single page-to-host channel. Everything the page initiates —
    /// listener registration and random-file requests — arrives here as one
    /// tagged object, so there is exactly one place that has to distrust the page.
    static let messageHandlerName = "mweWallpaper"

    static let hostScript = """
    (() => {
      if (window.__mweWallpaperHost) return;
      const post = message => {
        try { window.webkit.messageHandlers.\(WebWallpaperProtocol.messageHandlerName).postMessage(message); }
        catch (error) { console.error("wallpaper host channel unavailable", error); }
      };
      let listener = null;
      let lastUser = null, lastGeneral = null, lastPaused = null;
      // What the host has told this document about each watched directory, so a
      // listener registered after the files arrived still sees them.
      const directories = new Map();
      const call = (name, ...args) => {
        if (listener && typeof listener[name] === "function") {
          try { listener[name](...args); } catch (error) { console.error("wallpaperPropertyListener." + name + " failed", error); }
        }
      };
      // Wallpaper Engine only calls a listener that exists when the page has
      // loaded. Replaying the last values to a late listener is strictly more
      // forgiving, so bundled pages that register asynchronously still start.
      Object.defineProperty(window, "wallpaperPropertyListener", {
        configurable: true,
        get() { return listener; },
        set(value) {
          listener = value;
          if (lastGeneral) call("applyGeneralProperties", lastGeneral);
          if (lastUser) call("applyUserProperties", lastUser);
          if (lastPaused !== null) call("setPaused", lastPaused);
          for (const [property, files] of directories) {
            if (files.length) call("userDirectoryFilesAddedOrChanged", property, files.slice());
          }
        },
      });
      // Right clicks are forwarded to the page, never to WebKit's own context
      // menu: a wallpaper has no Reload or Inspect Element. Page handlers still run.
      window.addEventListener("contextmenu", event => event.preventDefault(), true);

      // Registration replaces, never accumulates: a page that re-registers, or
      // that is reloaded after a crash, must not end up receiving every frame
      // twice. The host is told only when the page crosses between having no
      // listener and having one, so capture opens and closes on real demand.
      let audioListener = null;
      window.wallpaperRegisterAudioListener = value => {
        const next = typeof value === "function" ? value : null;
        const had = audioListener !== null;
        audioListener = next;
        if ((next !== null) !== had) post({ type: next ? "audioSubscribed" : "audioUnsubscribed" });
      };

      const MEDIA_SLOTS = ["status", "properties", "thumbnail", "playback", "timeline"];
      const mediaListeners = {};
      const mediaValue = {};
      const mediaEncoded = {};
      const mediaCount = () => MEDIA_SLOTS.reduce((total, slot) => total + (mediaListeners[slot] ? 1 : 0), 0);
      const fireMedia = (slot, event) => {
        const target = mediaListeners[slot];
        if (!target) return;
        try { target(event); } catch (error) { console.error("wallpaper media listener " + slot + " failed", error); }
      };
      for (const slot of MEDIA_SLOTS) {
        mediaListeners[slot] = null;
        mediaValue[slot] = null;
        mediaEncoded[slot] = null;
        const name = "wallpaperRegisterMedia" + slot.charAt(0).toUpperCase() + slot.slice(1) + "Listener";
        window[name] = value => {
          const next = typeof value === "function" ? value : null;
          const before = mediaCount();
          mediaListeners[slot] = next;
          const after = mediaCount();
          if (before === 0 && after > 0) post({ type: "mediaSubscribed" });
          else if (before > 0 && after === 0) post({ type: "mediaUnsubscribed" });
          if (next && mediaValue[slot] !== null) fireMedia(slot, mediaValue[slot]);
        };
      }
      // The official documentation uses both spellings in its own examples.
      const PLAYING = 0, PAUSED = 1, STOPPED = 2;
      window.wallpaperMediaIntegration = Object.freeze({
        PLAYBACK_PLAYING: PLAYING, PLAYBACK_PAUSED: PAUSED, PLAYBACK_STOPPED: STOPPED,
        playback: Object.freeze({ PLAYING, PAUSED, STOPPED }),
      });

      let randomFileSequence = 0;
      const randomFileCallbacks = new Map();
      window.wallpaperRequestRandomFileForProperty = (property, callback) => {
        if (typeof property !== "string" || property === "" || typeof callback !== "function") return;
        const requestId = "r" + (++randomFileSequence);
        randomFileCallbacks.set(requestId, callback);
        post({ type: "randomFileRequest", requestId, propertyId: property });
      };

      window.__mweWallpaperHost = Object.freeze({
        applyUserProperties(properties) { lastUser = properties; call("applyUserProperties", properties); },
        applyGeneralProperties(properties) { lastGeneral = properties; call("applyGeneralProperties", properties); },
        setPaused(paused) { lastPaused = !!paused; call("setPaused", lastPaused); },
        deliverAudio(bins) {
          if (!audioListener) return;
          try { audioListener(bins); } catch (error) { console.error("wallpaperRegisterAudioListener callback failed", error); }
        },
        // Each media listener fires only when its own part changed. The host
        // already drops unchanged values, but a resume replay and a provider
        // re-emission can still race, so the last payload is compared here too.
        // Compared key by key in sorted order: the host builds these objects
        // from a dictionary, whose key order is not part of the contract.
        deliverMedia(slot, event) {
          if (!MEDIA_SLOTS.includes(slot)) return;
          const encoded = JSON.stringify(Object.keys(event).sort().map(key => [key, event[key]]));
          if (mediaEncoded[slot] === encoded) return;
          mediaEncoded[slot] = encoded;
          mediaValue[slot] = event;
          fireMedia(slot, event);
        },
        deliverRandomFile(requestId, property, filePath) {
          const callback = randomFileCallbacks.get(requestId);
          if (!callback) return;
          randomFileCallbacks.delete(requestId);
          try { callback(property, filePath); } catch (error) { console.error("wallpaperRequestRandomFileForProperty callback failed", error); }
        },
        userDirectoryFilesAddedOrChanged(property, files) {
          const known = directories.get(property) || [];
          directories.set(property, known.concat(files.filter(file => !known.includes(file))));
          call("userDirectoryFilesAddedOrChanged", property, files);
        },
        userDirectoryFilesRemoved(property, files) {
          const known = directories.get(property);
          if (known) directories.set(property, known.filter(file => !files.includes(file)));
          call("userDirectoryFilesRemoved", property, files);
        },
      });
    })();
    """
}
