import Foundation

/// Mirrored pages share output responsibility, not mutable page state or audio analysis.
enum WebWallpaperAudioOwnership {
    static func owners(
        in wallpapers: [UInt32: BridgeWebWallpaper], canPresent: (UInt32) -> Bool
    ) -> [UInt32: UInt32] {
        var owners: [UInt32: UInt32] = [:]
        for (displayID, wallpaper) in wallpapers
        where !wallpaper.paused && !wallpaper.muted && wallpaper.volume > 0
            && wallpaper.volume.isFinite && canPresent(displayID) {
            let source = wallpaper.audioSourceDisplayId
            if let previous = owners[source] {
                if previous != source && (displayID == source || displayID < previous) {
                    owners[source] = displayID
                }
            } else {
                owners[source] = displayID
            }
        }
        return owners
    }
}
