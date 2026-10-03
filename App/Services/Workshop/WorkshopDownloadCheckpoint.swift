import Foundation

/// SteamCMD reuses and verifies its own content manifests when resumed in a fresh private runtime.
/// These paths contain download data only. Login state and runtime files are never checkpoints.
enum WorkshopDownloadCheckpoint {
    private static let paths = ["steamapps", "wallpaper-engine"]

    static func restore(from checkpoint: URL, to staging: URL) throws {
        let files = FileManager.default
        for path in paths {
            let source = checkpoint.appendingPathComponent(path, isDirectory: true)
            guard files.fileExists(atPath: source.path) else { continue }
            let target = staging.appendingPathComponent(path, isDirectory: true)
            if files.fileExists(atPath: target.path) { try files.removeItem(at: target) }
            try files.moveItem(at: source, to: target)
        }
    }

    static func save(from staging: URL, to checkpoint: URL) throws {
        let files = FileManager.default
        let available = paths.filter { files.fileExists(atPath: staging.appendingPathComponent($0).path) }
        guard !available.isEmpty else { return }
        let pending = checkpoint.deletingLastPathComponent().appendingPathComponent(".partial-" + UUID().uuidString)
        try files.createDirectory(at: pending, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: pending) }
        for path in available {
            try files.moveItem(at: staging.appendingPathComponent(path), to: pending.appendingPathComponent(path))
        }
        try remove(at: checkpoint)
        try files.moveItem(at: pending, to: checkpoint)
    }

    static func remove(at checkpoint: URL) throws {
        do { try FileManager.default.removeItem(at: checkpoint) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { }
    }
}
