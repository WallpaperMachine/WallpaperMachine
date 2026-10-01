import CryptoKit
import Darwin
import Foundation

/// A package is an ordinary, finite directory tree, never an archive to extract.
/// Root-relative openat + O_NOFOLLOW also checks parents when bytes are read, so a
/// changed package cannot race validation into following a link outside the package.
struct WallpaperBackupFiles: Sendable {
    let limits: WallpaperBackupLimits
    private var manager: FileManager { .default }

    func validateRelative(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, path.utf8.count <= limits.maximumPathBytes,
              parts.count <= limits.maximumDepth,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":")
                && !$0.contains("\\") && !$0.contains("\0") }),
              (path as NSString).standardizingPath == path else { throw unsafe(path) }
    }

    func kind(at url: URL, rejectHardLinks: Bool = false) throws -> (WallpaperBackupEntry.Kind, Int64) {
        var status = stat()
        guard lstat(url.path, &status) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        switch status.st_mode & S_IFMT {
        case S_IFDIR: return (.directory, 0)
        case S_IFREG:
            guard !rejectHardLinks || status.st_nlink == 1 else { throw unsafe(url.lastPathComponent) }
            guard status.st_size >= 0, status.st_size <= limits.maximumFileBytes else { throw oversized() }
            return (.file, status.st_size)
        default: throw unsafe(url.lastPathComponent)
        }
    }

    func openReading(root: URL, path: String, rejectHardLinks: Bool) throws -> FileHandle {
        try validateRelative(path)
        var descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw unsafe(root.lastPathComponent) }
        let parts = path.split(separator: "/").map(String.init)
        for (index, part) in parts.enumerated() {
            let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
                | (index == parts.count - 1 ? 0 : O_DIRECTORY)
            let next = openat(descriptor, part, flags)
            close(descriptor)
            guard next >= 0 else { throw unsafe(path) }
            descriptor = next
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
              !rejectHardLinks || status.st_nlink == 1,
              status.st_size >= 0, status.st_size <= limits.maximumFileBytes else {
            close(descriptor)
            throw unsafe(path)
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    func scan(_ root: URL, rejectingHardLinks: Bool = false) throws -> [WallpaperBackupEntry] {
        guard try kind(at: root).0 == .directory else { throw unsafe(root.lastPathComponent) }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = canonicalRoot.pathComponents
        var entries: [WallpaperBackupEntry] = []
        var bytes: Int64 = 0
        var enumerationError: Error?
        guard let enumerator = manager.enumerator(at: canonicalRoot, includingPropertiesForKeys: nil, options: [],
            errorHandler: { _, error in enumerationError = error; return false }) else { throw unsafe(root.lastPathComponent) }
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let (kind, size) = try kind(at: url, rejectHardLinks: rejectingHardLinks)
            let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            guard components.count > rootComponents.count, components.starts(with: rootComponents) else {
                throw unsafe(url.lastPathComponent)
            }
            let path = components.dropFirst(rootComponents.count).joined(separator: "/")
            try validateRelative(path)
            guard entries.count < limits.maximumEntries, size <= limits.maximumBytes - bytes else {
                throw oversized()
            }
            bytes += size
            entries.append(.init(path: path, kind: kind, size: size))
        }
        if let enumerationError { throw enumerationError }
        return entries
    }

    /// Streams bounded chunks and verifies size/digest before accepting the copy. A
    /// hard-linked source is copied independently; package and pending files reject links.
    @discardableResult
    func stream(root: URL, entry: WallpaperBackupEntry, to destination: URL? = nil,
                rejectHardLinks: Bool = true) throws -> String {
        let input = try openReading(root: root, path: entry.path, rejectHardLinks: rejectHardLinks)
        defer { try? input.close() }
        var output: FileHandle?
        if let destination {
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        }
        defer { try? output?.close() }
        var hash = SHA256()
        var count: Int64 = 0
        while true {
            try Task.checkCancellation()
            guard let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            guard Int64(chunk.count) <= entry.size - count else { throw changed() }
            count += Int64(chunk.count)
            hash.update(data: chunk)
            try output?.write(contentsOf: chunk)
        }
        let digest = Self.digest(hash.finalize())
        guard count == entry.size, entry.digest == nil || entry.digest == digest else { throw changed() }
        try output?.synchronize()
        return digest
    }

    func readMetadata(root: URL, path: String, maximum: Int) throws -> Data {
        let input = try openReading(root: root, path: path, rejectHardLinks: true)
        defer { try? input.close() }
        guard let data = try input.read(upToCount: maximum + 1), data.count <= maximum else { throw oversized() }
        return data
    }

    func copyTree(from source: URL, to destination: URL, rejectingHardLinks: Bool = false) throws {
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in try scan(source, rejectingHardLinks: rejectingHardLinks) {
            let target = destination.appendingPathComponent(entry.path)
            if entry.kind == .directory {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try stream(root: source, entry: entry, to: target, rejectHardLinks: rejectingHardLinks)
            }
        }
    }

    static func digest(_ data: Data) -> String { digest(SHA256.hash(data: data)) }
    private static func digest(_ hash: SHA256.Digest) -> String {
        hash.map { String(format: "%02x", $0) }.joined()
    }
    func unsafe(_ path: String) -> WallpaperBackupFailure {
        .init(message: String(localized: "The backup contains an unsafe path, link or special file: \(path)"))
    }
    func oversized() -> WallpaperBackupFailure {
        .init(message: String(localized: "This backup exceeds the supported file, size or manifest limits."))
    }
    func changed() -> WallpaperBackupFailure {
        .init(message: String(localized: "The backup changed after it was reviewed. Preview it again before restoring."))
    }
}
