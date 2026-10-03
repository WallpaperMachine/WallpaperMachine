import Foundation
import Observation

/// Offers support once a successfully downloaded wallpaper has been applied.
@MainActor
@Observable
final class SupportPromptStore {
    private struct State: Codable {
        var downloadedWallpaperIDs: Set<String> = []
        var pending = false
        var presented = false
    }

    private static let key = "WallpaperMachine.supportPrompt.state"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var state: State
    private(set) var isPending: Bool

    init(defaults: UserDefaults = ClientPreferences.defaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do {
                state = try JSONDecoder().decode(State.self, from: data)
            } catch {
                AppLog.warn("support prompt state could not be loaded: \(error.localizedDescription)")
                state = State()
            }
        } else {
            state = State()
        }
        isPending = state.pending && !state.presented
    }

    func recordDownload(wallpaperID: String) {
        guard !wallpaperID.isEmpty, !state.pending, !state.presented,
              !state.downloadedWallpaperIDs.contains(wallpaperID) else { return }
        var next = state
        next.downloadedWallpaperIDs.insert(wallpaperID)
        persist(next)
    }

    func recordSuccessfulActivation(wallpaperID: String) {
        guard !wallpaperID.isEmpty, !state.pending, !state.presented,
              state.downloadedWallpaperIDs.contains(wallpaperID) else { return }
        var next = state
        next.downloadedWallpaperIDs.removeAll()
        next.pending = true
        persist(next)
    }

    func forgetDownload(wallpaperID: String) {
        guard state.downloadedWallpaperIDs.contains(wallpaperID) else { return }
        var next = state
        next.downloadedWallpaperIDs.remove(wallpaperID)
        persist(next)
    }

    func markPresented() {
        guard isPending else { return }
        var next = state
        next.pending = false
        next.presented = true
        persist(next)
    }

    private func persist(_ next: State) {
        do {
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: Self.key)
            state = next
            isPending = next.pending && !next.presented
        } catch {
            AppLog.warn("support prompt state could not be saved: \(error.localizedDescription)")
        }
    }
}
