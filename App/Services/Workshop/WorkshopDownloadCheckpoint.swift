import Foundation

/// SteamCMD reuses and verifies its own content manifests when resumed in a fresh private runtime.
/// These paths contain download data only. Login state and runtime files are never checkpoints.
enum WorkshopDownloadCheckpoint {
    private static let paths = ["steamapps", "wallpaper-engine"]

    private static func pendingURL(for checkpoint: URL) -> URL {
        checkpoint.deletingLastPathComponent().appendingPathComponent(".partial-" + checkpoint.lastPathComponent)
    }

    private static func backupURL(for checkpoint: URL) -> URL {
        checkpoint.deletingLastPathComponent().appendingPathComponent(".previous-" + checkpoint.lastPathComponent)
    }

    static func restore(from checkpoint: URL, to staging: URL) throws {
        let files = FileManager.default
        // A crash or failed rename can leave publication incomplete. Each content directory
        // was moved intact; prefer the new copy, then the published copy, then its backup.
        let candidates = [pendingURL(for: checkpoint), checkpoint, backupURL(for: checkpoint)]
        for path in paths {
            guard let source = candidates.map({ $0.appendingPathComponent(path, isDirectory: true) })
                .first(where: { files.fileExists(atPath: $0.path) }) else { continue }
            let target = staging.appendingPathComponent(path, isDirectory: true)
            if files.fileExists(atPath: target.path) { try files.removeItem(at: target) }
            try files.moveItem(at: source, to: target)
        }
        try remove(at: checkpoint)
    }

    static func save(from staging: URL, to checkpoint: URL) throws {
        let files = FileManager.default
        let available = paths.filter { files.fileExists(atPath: staging.appendingPathComponent($0).path) }
        guard !available.isEmpty else { return }
        let pending = pendingURL(for: checkpoint)
        let backup = backupURL(for: checkpoint)
        try files.createDirectory(at: pending, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Do not delete pending on failure: restore recognizes it after a failed publication
        // or process interruption, including a partial move of the two content directories.
        for path in available {
            try files.moveItem(at: staging.appendingPathComponent(path), to: pending.appendingPathComponent(path))
        }
        if files.fileExists(atPath: checkpoint.path) {
            try removeDirectory(at: backup)
            try files.moveItem(at: checkpoint, to: backup)
        }
        try files.moveItem(at: pending, to: checkpoint)
        try removeDirectory(at: backup)
    }

    static func remove(at checkpoint: URL) throws {
        for directory in [pendingURL(for: checkpoint), checkpoint, backupURL(for: checkpoint)] {
            try removeDirectory(at: directory)
        }
    }

    private static func removeDirectory(at directory: URL) throws {
        do { try FileManager.default.removeItem(at: directory) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { }
    }
}
