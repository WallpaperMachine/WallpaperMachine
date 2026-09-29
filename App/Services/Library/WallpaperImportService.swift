import Darwin
import Foundation

/// Copies user imports non-destructively and adopts validated private Steam downloads.
actor WallpaperImportService {
    enum DuplicatePolicy: String, CaseIterable, Identifiable, Sendable {
        case skip = "Skip existing"
        case keepBoth = "Keep both copies"
        var id: String { rawValue }
    }

    struct Report: Sendable {
        var importedIDs: [String] = []
        var skipped: [String] = []
        var failures: [String] = []
        var cancelled = false
    }

    struct ImportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv", "avi"]
    static let webExtensions: Set<String> = ["html", "htm"]
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif",
    ]
    /// Pictures a web view shows as they are. Any other format is shown from a JPEG copy, so a
    /// wallpaper never depends on which formats this macOS release's WebKit happens to decode.
    static let webImageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp"]
    /// A picture is read into memory whole to measure and scale it.
    static let maximumImageBytes = 512 * 1024 * 1024
    /// Library ids of imported pictures start with this, so the panel can tell a still image
    /// it packaged from a web wallpaper someone wrote.
    static let imageIDPrefix = "image-"

    private let downscale: @Sendable (Data, Int) throws -> Data

    /// `downscale` re-encodes an image as a JPEG no larger than the given pixel size; the app
    /// uses the thumbnail cache's ImageIO encoder, which also proves the bytes decode.
    init(
        downscale: @escaping @Sendable (Data, Int) throws -> Data = {
            try WorkshopThumbnailCache.encodeThumbnail($0, maxPixelSize: $1)
        }
    ) {
        self.downscale = downscale
    }

    func importItems(
        _ sources: [URL], into library: URL, duplicates: DuplicatePolicy,
        progress: @Sendable (String) async -> Void
    ) async throws -> Report {
        let fm = FileManager.default
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        let managedRoot = library.resolvingSymlinksInPath().standardizedFileURL
        // A sibling staging directory is on the same volume but invisible to the library scanner.
        let staging = managedRoot.deletingLastPathComponent()
            .appendingPathComponent(".WallpaperMachine-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        var report = Report()
        var seen = Set<String>()

        for source in sources {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                try Task.checkCancellation()
                let candidates = try discover(source)
                for candidate in candidates {
                    try Task.checkCancellation()
                    let canonical = candidate.resolvingSymlinksInPath().standardizedFileURL
                    guard seen.insert(canonical.path).inserted else { continue }
                    await progress(String(localized: "Importing \(candidate.lastPathComponent)…"))
                    do {
                        guard !isWithin(canonical, managedRoot), !isWithin(managedRoot, canonical) else {
                            throw ImportError(message: String(localized: "Choose a source outside WallpaperMachine’s managed library."))
                        }
                        let isDirectory = try candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                        let ext = candidate.pathExtension.lowercased()
                        let isImage = !isDirectory && Self.imageExtensions.contains(ext)
                        let preferredID = isDirectory ? candidate.lastPathComponent
                            : (isImage ? Self.imageIDPrefix : "local-") + candidate.lastPathComponent
                        guard isSafeRelativePath(preferredID), !preferredID.contains("/") else {
                            throw ImportError(message: String(localized: "The folder name cannot be used as a library identifier."))
                        }
                        var id = preferredID
                        var destination = managedRoot.appendingPathComponent(id, isDirectory: true)
                        if fm.fileExists(atPath: destination.path) {
                            if duplicates == .skip {
                                try validateProject(at: destination)
                                report.skipped.append(candidate.lastPathComponent)
                                continue
                            }
                            id += "-" + UUID().uuidString
                            destination = managedRoot.appendingPathComponent(id, isDirectory: true)
                        }
                        let staged = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
                        defer { try? fm.removeItem(at: staged) }
                        if isDirectory {
                            try validateProject(at: candidate)
                            try copySafely(candidate, to: staged)
                        } else if isImage {
                            try packageImage(candidate, extension: ext, into: staged)
                        } else {
                            guard Self.videoExtensions.contains(ext) || Self.webExtensions.contains(ext) else {
                                throw ImportError(message: String(localized: "Choose a video, image, HTML file, or Wallpaper Engine project folder."))
                            }
                            try fm.createDirectory(at: staged, withIntermediateDirectories: false)
                            try copySafely(candidate, to: staged.appendingPathComponent(candidate.lastPathComponent))
                            let manifest: [String: Any] = [
                                "title": candidate.deletingPathExtension().lastPathComponent,
                                "type": Self.videoExtensions.contains(ext) ? "video" : "web",
                                "file": candidate.lastPathComponent,
                                "general": ["properties": [String: String]()]
                            ]
                            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                            try data.write(to: staged.appendingPathComponent("project.json"), options: .atomic)
                        }
                        try validateProject(at: staged)
                        try Task.checkCancellation()
                        // moveItem never overwrites a concurrently created destination.
                        try fm.moveItem(at: staged, to: destination)
                        report.importedIDs.append(id)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        report.failures.append("\(candidate.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            } catch is CancellationError {
                report.cancelled = true
                break
            } catch {
                report.failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Packages one picture as a `StillImageWallpaper` in `staged`. The original keeps its bytes
    /// under a fixed name, so no file name from disk reaches the page's markup, and the title
    /// is the file's name.
    private func packageImage(_ source: URL, extension ext: String, into staged: URL) throws {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= Self.maximumImageBytes else {
            throw ImportError(message: String(localized: "Images must be regular files between 1 byte and 512 MB."))
        }
        let image = try Data(contentsOf: source, options: .mappedIfSafe)
        let unreadable = ImportError(message: String(localized: "This image could not be read. Choose a picture that opens in Preview."))
        guard let pixels = StillImageWallpaper.pixelSize(of: image) else { throw unreadable }
        let longest = max(pixels.width, pixels.height)
        let preview: Data
        var display: Data?
        do {
            preview = try downscale(image, StillImageWallpaper.previewPixels)
            if !Self.webImageExtensions.contains(ext) || longest > StillImageWallpaper.displayPixels {
                display = try downscale(image, min(longest, StillImageWallpaper.displayPixels))
            }
        } catch {
            throw unreadable
        }
        try Task.checkCancellation()
        let fm = FileManager.default
        try fm.createDirectory(at: staged, withIntermediateDirectories: false)
        let imageFile = "image.\(ext)"
        try image.write(to: staged.appendingPathComponent(imageFile))
        try preview.write(to: staged.appendingPathComponent(StillImageWallpaper.previewFile))
        if let display { try display.write(to: staged.appendingPathComponent(StillImageWallpaper.displayFile)) }
        let fit = StillImageWallpaper.Fit.preferred(width: pixels.width, height: pixels.height)
        try Data(StillImageWallpaper.page(showing: display == nil ? imageFile : StillImageWallpaper.displayFile, fit: fit).utf8)
            .write(to: staged.appendingPathComponent(StillImageWallpaper.entryFile))
        let manifest: [String: Any] = [
            "title": source.deletingPathExtension().lastPathComponent,
            "type": "web",
            "file": StillImageWallpaper.entryFile,
            "preview": StillImageWallpaper.previewFile,
            "general": ["properties": StillImageWallpaper.properties(fit: fit)],
            "image": ["file": imageFile, "width": pixels.width, "height": pixels.height],
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: staged.appendingPathComponent("project.json"), options: .atomic)
    }

    /// Consumes a complete item from disposable Steam staging without copying payload bytes.
    /// A valid existing item is left untouched unless `replacing`, when the new tree takes its
    /// place; the caller remains responsible for staging cleanup.
    func importDownloadedItem(_ itemID: String, from staging: URL, into library: URL, replacing: Bool = false) throws {
        try Task.checkCancellation()
        guard !itemID.isEmpty, itemID.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let numericID = UInt64(itemID), numericID > 0 else {
            throw ImportError(message: String(localized: "Choose a valid numeric Workshop item identifier."))
        }
        let fm = FileManager.default
        let stagingRoot = staging.standardizedFileURL
        let canonicalStaging = stagingRoot.resolvingSymlinksInPath().standardizedFileURL
        var managedRoot = library.resolvingSymlinksInPath().standardizedFileURL
        guard !isWithin(canonicalStaging, managedRoot), !isWithin(managedRoot, canonicalStaging) else {
            throw ImportError(message: String(localized: "Download staging must be outside the managed library."))
        }

        // Check each fixed ancestor before descending: resolving the final path alone would
        // silently accept a Steam content directory redirected through a symbolic link.
        var source = stagingRoot
        try requireDownloadDirectory(source)
        for component in ["steamapps", "workshop", "content", "431960", itemID] {
            try Task.checkCancellation()
            source.appendPathComponent(component, isDirectory: true)
            try requireDownloadDirectory(source)
        }
        try validateDownloadedProject(at: source)
        try Task.checkCancellation()
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        managedRoot = library.resolvingSymlinksInPath().standardizedFileURL
        guard !isWithin(canonicalStaging, managedRoot), !isWithin(managedRoot, canonicalStaging) else {
            throw ImportError(message: String(localized: "Download staging must be outside the managed library."))
        }
        let destination = managedRoot.appendingPathComponent(itemID, isDirectory: true)
        try Task.checkCancellation()
        if replacing, let installed = try? downloadMetadata(at: destination), installed.st_mode & S_IFMT == S_IFDIR {
            // Only an installed wallpaper is replaced: the old tree ends up in staging, which the
            // caller clears, so a folder that is not one is left where it is.
            do {
                try validateProject(at: destination)
            } catch {
                throw ImportError(message: String(localized: "The library’s folder for Workshop item \(itemID) is not an installed wallpaper, so its update was not put in its place. Move the folder out of the library and download the item again."))
            }
            // An update swaps the new tree in and the old one out in one step, so the library never
            // lacks the wallpaper and a failure leaves the old version where it was.
            let result = source.path.withCString { sourcePath in
                destination.path.withCString { destinationPath in
                    renamex_np(sourcePath, destinationPath, UInt32(RENAME_SWAP))
                }
            }
            guard result == 0 else {
                let code = errno
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [
                    NSFilePathErrorKey: destination.path,
                    NSLocalizedDescriptionKey: String(localized: "Could not replace Workshop item \(itemID) with its update: \(String(cString: strerror(code))). The installed version is unchanged.")
                ])
            }
            return
        }
        // Unlike moveItem, this cannot fall back to a cross-volume copy. RENAME_EXCL
        // atomically refuses even a destination created after our validation.
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            let code = errno
            if code == EEXIST {
                try validateDownloadedProject(at: destination)
                try Task.checkCancellation()
                return
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [
                NSFilePathErrorKey: destination.path,
                NSLocalizedDescriptionKey: String(localized: "Could not publish Workshop item \(itemID): \(String(cString: strerror(code))). Download staging and the library must be on the same volume.")
            ])
        }
    }

    private func downloadMetadata(at url: URL) throws -> stat {
        var metadata = stat()
        // URL directory representations can include a trailing slash, which makes
        // lstat follow a final symlink. URL.path removes that directory marker.
        let result = url.path.withCString { lstat($0, &metadata) }
        guard result == 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: url.path])
        }
        return metadata
    }

    private func requireDownloadDirectory(_ url: URL) throws {
        let metadata = try downloadMetadata(at: url)
        guard metadata.st_mode & S_IFMT == S_IFDIR else {
            throw ImportError(message: String(localized: "Download directories must be real folders, not symbolic links or special files: \(url.lastPathComponent)."))
        }
    }

    private func validateDownloadedProject(at root: URL) throws {
        try requireDownloadDirectory(root)
        var pending = [root]
        while let next = pending.popLast() {
            try Task.checkCancellation()
            let metadata = try downloadMetadata(at: next)
            switch metadata.st_mode & S_IFMT {
            case S_IFDIR:
                pending.append(contentsOf: try FileManager.default.contentsOfDirectory(at: next, includingPropertiesForKeys: nil))
            case S_IFREG:
                break
            default:
                throw ImportError(message: String(localized: "Downloaded projects may contain only regular files and folders, not symbolic links or special files: \(next.lastPathComponent)."))
            }
        }
        try Task.checkCancellation()
        try validateProject(at: root, requireNonemptyContent: true)
    }

    private func discover(_ source: URL) throws -> [URL] {
        let fm = FileManager.default
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw ImportError(message: String(localized: "Symbolic links are not imported. Choose the original folder or file instead."))
        }
        guard values.isDirectory == true else { return [source] }
        if fm.fileExists(atPath: source.appendingPathComponent("project.json").path) { return [source] }
        let relativeRoots = ["", "steamapps/workshop/content/431960", "workshop/content/431960", "content/431960", "431960"]
        var projects: [URL] = []
        for relative in relativeRoots {
            try Task.checkCancellation()
            let root = relative.isEmpty ? source : source.appendingPathComponent(relative, isDirectory: true)
            guard fm.fileExists(atPath: root.path) else { continue }
            guard isWithin(root.resolvingSymlinksInPath().standardizedFileURL,
                           source.resolvingSymlinksInPath().standardizedFileURL) else { continue }
            let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            for child in children where fm.fileExists(atPath: child.appendingPathComponent("project.json").path) {
                projects.append(child)
            }
        }
        guard !projects.isEmpty else {
            throw ImportError(message: String(localized: "No project.json found. Choose a wallpaper project, a folder containing projects, or a Steam library with steamapps/workshop/content/431960."))
        }
        return projects.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func validateProject(at root: URL, requireNonemptyContent: Bool = false) throws {
        let manifestURL = root.appendingPathComponent("project.json")
        let metadata = try manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard metadata.isRegularFile == true, metadata.isSymbolicLink != true,
              (metadata.fileSize ?? 0) <= 16 * 1024 * 1024 else {
            throw ImportError(message: String(localized: "project.json must be a regular JSON file smaller than 16 MB."))
        }
        let manifestData = try Data(contentsOf: manifestURL)
        guard String(data: manifestData, encoding: .utf8) != nil, !manifestData.starts(with: [0xEF, 0xBB, 0xBF]) else {
            throw ImportError(message: String(localized: "project.json must use UTF-8 encoding without a byte-order mark. Convert the manifest and import it again."))
        }
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let type = (manifest["type"] as? String)?.lowercased(), ["scene", "video", "web"].contains(type) else {
            throw ImportError(message: String(localized: "project.json must describe a scene, video, or web wallpaper."))
        }
        if let value = manifest["file"], !(value is String) {
            throw ImportError(message: String(localized: "The project’s file field must be a relative filename."))
        }
        let file = (manifest["file"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (type == "scene" ? "scene.json" : "")
        guard isSafeRelativePath(file) else {
            throw ImportError(message: String(localized: "The project’s file field must point inside its own folder (no absolute paths or parent traversal)."))
        }
        let entry = root.appendingPathComponent(file)
        let package = entry.deletingPathExtension().appendingPathExtension("pkg")
        let entryValues = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        let packageValues = type == "scene" ? (try? package.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])) : nil
        let exists = (entryValues?.isRegularFile == true && entryValues?.isSymbolicLink != true
                      && (!requireNonemptyContent || (entryValues?.fileSize ?? 0) > 0))
            || (packageValues?.isRegularFile == true && packageValues?.isSymbolicLink != true
                && (!requireNonemptyContent || (packageValues?.fileSize ?? 0) > 0))
        guard exists else {
            throw ImportError(message: String(localized: "Missing project content: \(file). Copy the complete wallpaper folder, not just project.json."))
        }
        if let preview = manifest["preview"] as? String, !preview.isEmpty, !isSafeRelativePath(preview) {
            throw ImportError(message: String(localized: "The preview path must remain inside the wallpaper folder."))
        }
        if let dependencies = manifest["dependencies"] as? [String], dependencies.contains(where: { !isSafeRelativePath($0) }) {
            throw ImportError(message: String(localized: "Project dependency paths may not escape their folder."))
        }
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.contains("\0") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private func isWithin(_ child: URL, _ parent: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path.hasSuffix("/") ? parent.path : parent.path + "/")
    }

    private func copySafely(_ source: URL, to destination: URL) throws {
        try Task.checkCancellation()
        let fm = FileManager.default
        let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
        guard values.isSymbolicLink != true else {
            throw ImportError(message: String(localized: "Symbolic links are not imported: \(source.lastPathComponent). Copy the original content into the project folder first."))
        }
        if values.isDirectory == true {
            try fm.createDirectory(at: destination, withIntermediateDirectories: false)
            let children = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            for child in children {
                try copySafely(child, to: destination.appendingPathComponent(child.lastPathComponent))
            }
        } else if values.isRegularFile == true {
            guard fm.createFile(atPath: destination.path, contents: nil) else {
                throw ImportError(message: String(localized: "Could not create \(destination.lastPathComponent). Check available disk space and folder permissions."))
            }
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            while true {
                try Task.checkCancellation()
                guard let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
            }
            try output.synchronize()
        } else {
            throw ImportError(message: String(localized: "Unsupported special file: \(source.lastPathComponent). Only regular files and folders can be imported."))
        }
    }
}
