import CryptoKit
import Foundation

/// Scans an active project's file identities once per library/content refresh.
actor WallpaperProjectRevision {
    private var cache: [String: (revision: UInt64, fingerprint: String)] = [:]

    func fingerprint(_ directory: URL, revision: UInt64) throws -> String {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        if let value = cache[root.path], value.revision == revision { return value.fingerprint }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        var scanError: Error?
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
            errorHandler: { _, error in scanError = error; return false }) else {
            throw CocoaError(.fileReadUnknown)
        }
        var rows: [[String]] = []
        for case let url as URL in files {
            try Task.checkCancellation()
            let relative = url.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            if relative == UserAssetStore.stagingDirectoryName {
                files.skipDescendants()
                continue
            }
            guard rows.count < 200_000 else { throw CocoaError(.fileReadTooLarge) }
            let values = try url.resourceValues(forKeys: keys)
            var link = ""
            if values.isSymbolicLink == true {
                files.skipDescendants()
                link = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
            }
            rows.append([relative, String(values.fileSize ?? 0),
                String(values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0),
                values.fileResourceIdentifier.map { String(describing: $0) } ?? "", link])
        }
        if let scanError { throw scanError }
        let data = try JSONEncoder().encode(rows.sorted { $0[0] < $1[0] })
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if cache.count >= 64 { cache.removeAll() }
        cache[root.path] = (revision, fingerprint)
        return fingerprint
    }
}
