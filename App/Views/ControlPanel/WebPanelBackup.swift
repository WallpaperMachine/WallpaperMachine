import Foundation

@MainActor
extension WebPanelController {
    func performBackup(_ action: String, request: WebPanelRequest) async throws -> Bool {
        switch action {
        case "backupExport":
            try await backup.export(includeLibrary: request.boolean("includeLibrary"))
        case "backupPreview":
            try await backup.choosePreview()
        case "backupRestore":
            guard let policy = WallpaperBackupConflictPolicy(rawValue: try request.string("conflictPolicy")) else {
                throw WebPanelRequest.invalid
            }
            try await backup.stageRestore(policy: policy)
        case "backupCancel":
            backup.cancel()
        case "backupCancelRestore":
            try backup.cancelRestore()
        default: return false
        }
        scheduleUpdate()
        return true
    }

    func trackBackupDependencies() {
        _ = backup.busy
        _ = backup.status
        _ = backup.error
        _ = backup.preview
        _ = backup.pendingRestore
    }

    /// Value for the top-level `backup` field, not a second snapshot envelope.
    func backupSnapshot() -> [String: Any] {
        var snapshot: [String: Any] = ["busy": backup.busy, "pendingRestore": backup.pendingRestore]
        if let status = backup.status { snapshot["status"] = status }
        if let error = backup.error { snapshot["error"] = error }
        if let preview = backup.preview {
            snapshot["preview"] = [
                "name": preview.name,
                "createdAt": preview.createdAt.timeIntervalSince1970 * 1_000,
                "wallpaperCount": preview.wallpaperCount,
                "presetCount": preview.presetCount,
                "collectionCount": preview.collectionCount,
                "includesLibrary": preview.includesLibrary,
                "byteCount": preview.byteCount,
                "conflicts": preview.conflicts,
                "warnings": preview.warnings,
            ] as [String: Any]
        }
        return snapshot
    }
}
