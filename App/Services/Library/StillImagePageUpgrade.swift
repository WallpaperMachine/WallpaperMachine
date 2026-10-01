import Foundation
import Darwin
import ImageIO

/// Only this app's fixed, unmodified templates may be upgraded. Neither an image-/pixiv-
/// identifier nor source metadata alone authorizes replacing arbitrary HTML.
enum StillImagePageUpgrade {
    struct Result: Sendable {
        let imageFile: String
        let fit: StillImageWallpaper.Fit
        let imageAspectRatio: Double
        let imagePixelSize: CGSize?
        let upgraded: Bool
    }
    private struct Candidate {
        let result: Result
        let page: URL
        let before: Data
        let replacement: Data?
    }
    fileprivate struct FileIdentity: Equatable, Sendable {
        let device: Int64
        let inode: UInt64
        let mode: UInt32
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
    }

    struct Stamp: Equatable, Sendable {
        fileprivate let directory: FileIdentity?
        fileprivate let page: FileIdentity?
        fileprivate let resources: [FileIdentity?]

        fileprivate func sameResources(as other: Stamp) -> Bool {
            directory == other.directory && resources == other.resources
        }
    }

    struct Evaluation: Sendable {
        /// Nil means the package changed during inspection; it is not a negative cache entry.
        let stamp: Stamp?
        let result: Result?
        let pageUpgraded: Bool
    }

    private static let resourceFiles = ["project.json", StillImageWallpaper.displayFile]
        + WallpaperImportService.imageExtensions.sorted().flatMap { ["image.\($0)", "illustration.\($0)"] }
    static let maximumMetadataBytes = 128 * 1024

    static func inspect(wallpaperID: String, project: URL, library: URL = ClientPaths.libraryURL) throws -> Result? {
        try candidate(wallpaperID: wallpaperID, project: project, library: library)?.result
    }

    /// A cold-path operation, invoked before loading the WebView. Writes only index.html;
    /// original image bytes, display copies, properties and manifest are never modified.
    static func prepare(wallpaperID: String, project: URL, library: URL = ClientPaths.libraryURL) throws -> Result? {
        try evaluate(wallpaperID: wallpaperID, project: project, library: library,
                     expectedStamp: stamp(project: project), upgrade: true).result
    }

    /// Inspection and upgrade are bound to the requested version, including negative results.
    /// The hook is a deterministic race seam; production never supplies one.
    static func evaluate(wallpaperID: String, project: URL, library: URL, expectedStamp: Stamp,
                         upgrade: Bool, beforeValidation: (@Sendable () throws -> Void)? = nil) throws -> Evaluation {
        let changed = Evaluation(stamp: nil, result: nil, pageUpgraded: false)
        guard stamp(project: project) == expectedStamp else { return changed }
        let candidate = try candidate(wallpaperID: wallpaperID, project: project, library: library)
        try beforeValidation?()
        try Task.checkCancellation()
        guard stamp(project: project) == expectedStamp else { return changed }
        guard let candidate else {
            return Evaluation(stamp: expectedStamp, result: nil, pageUpgraded: false)
        }
        guard upgrade, let replacement = candidate.replacement else {
            return Evaluation(stamp: expectedStamp, result: candidate.result, pageUpgraded: false)
        }
        // Recheck both exact authored bytes and resource identity immediately before committing.
        guard try boundedFile(candidate.page) == candidate.before,
              stamp(project: project) == expectedStamp else { return changed }
        try Task.checkCancellation()
        try replacement.write(to: candidate.page, options: .atomic)
        let committedStamp = stamp(project: project)
        guard committedStamp.sameResources(as: expectedStamp),
              (try? boundedFile(candidate.page)) == replacement,
              stamp(project: project) == committedStamp else {
            return Evaluation(stamp: nil, result: nil, pageUpgraded: true)
        }
        return Evaluation(stamp: committedStamp, result: candidate.result, pageUpgraded: true)
    }

    /// A fixed set of lstat calls: no directory enumeration, contents, or image decoding.
    /// Inode and nanosecond ctime also catch atomic replacements and same-sized in-place writes.
    static func stamp(project: URL) -> Stamp {
        Stamp(directory: fileIdentity(project, identityOnly: true),
              page: fileIdentity(project.appendingPathComponent(StillImageWallpaper.entryFile)),
              resources: resourceFiles.map { fileIdentity(project.appendingPathComponent($0)) })
    }

    private static func fileIdentity(_ file: URL, identityOnly: Bool = false) -> FileIdentity? {
        var info = stat()
        guard file.path.withCString({ lstat($0, &info) }) == 0 else { return nil }
        return FileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino), mode: UInt32(info.st_mode),
            size: identityOnly ? 0 : info.st_size,
            modifiedSeconds: identityOnly ? 0 : Int64(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: identityOnly ? 0 : Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: identityOnly ? 0 : Int64(info.st_ctimespec.tv_sec),
            changedNanoseconds: identityOnly ? 0 : Int64(info.st_ctimespec.tv_nsec))
    }

    private static func candidate(wallpaperID: String, project: URL, library: URL) throws -> Candidate? {
        guard validID(wallpaperID) else { return nil }
        let root = library.resolvingSymlinksInPath().standardizedFileURL
        let folder = project.standardizedFileURL
        let expected = root.appendingPathComponent(wallpaperID, isDirectory: true).standardizedFileURL
        guard folder.resolvingSymlinksInPath().path == expected.path,
              let directory = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              directory.isDirectory == true, directory.isSymbolicLink != true,
              let metadata = try boundedFile(folder.appendingPathComponent("project.json")),
              let manifest = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              manifest["type"] as? String == "web", manifest["file"] as? String == StillImageWallpaper.entryFile,
              let general = manifest["general"] as? [String: Any],
              let properties = general["properties"] as? [String: Any],
              let fitProperty = properties["fit"] as? [String: Any],
              let fitName = fitProperty["value"] as? String, let fit = StillImageWallpaper.Fit(rawValue: fitName)
        else { return nil }

        let provenance: [String: Any]
        let originalPrefix: String
        if wallpaperID.hasPrefix("image-"), let image = manifest["image"] as? [String: Any] {
            provenance = image
            originalPrefix = "image."
        } else if wallpaperID.hasPrefix("pixiv-"), let pixiv = manifest["pixiv"] as? [String: Any],
                  let workID = pixiv["id"] as? String, PixivWork.isValidID(workID),
                  let page = pixiv["page"] as? Int, page >= 0,
                  wallpaperID == "pixiv-\(workID)-p\(page)" {
            provenance = pixiv
            originalPrefix = "illustration."
        } else { return nil }
        guard let original = provenance["file"] as? String,
              original == originalPrefix + URL(fileURLWithPath: original).pathExtension.lowercased(),
              WallpaperImportService.imageExtensions.contains(URL(fileURLWithPath: original).pathExtension.lowercased()),
              isImageFile(folder.appendingPathComponent(original)),
              let width = provenance["width"] as? NSNumber, let height = provenance["height"] as? NSNumber,
              width.doubleValue.isFinite, height.doubleValue.isFinite,
              width.doubleValue > 0, height.doubleValue > 0
        else { return nil }
        let ratio = width.doubleValue / height.doubleValue
        guard ratio.isFinite, ratio > 0 else { return nil }
        let pageURL = folder.appendingPathComponent(StillImageWallpaper.entryFile)
        guard let page = try boundedFile(pageURL) else { return nil }
        var files = [original]
        if isImageFile(folder.appendingPathComponent(StillImageWallpaper.displayFile)) {
            files.insert(StillImageWallpaper.displayFile, at: 0)
        }
        for file in files {
            let current = Data(StillImageWallpaper.page(showing: file, fit: fit).utf8)
            let legacy = Data(StillImageWallpaper.legacyPage(showing: file, fit: fit).utf8)
            guard page == current || page == legacy else { continue }
            let needsUpgrade = page == legacy
            guard let size = imagePixelSize(folder.appendingPathComponent(file)) else { continue }
            let actualRatio = size.width / size.height
            return Candidate(result: Result(imageFile: file, fit: fit, imageAspectRatio: actualRatio,
                             imagePixelSize: size, upgraded: needsUpgrade),
                             page: pageURL, before: page, replacement: needsUpgrade ? current : nil)
        }
        return nil
    }

    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 1024 && id != "." && id != ".."
            && !id.contains("/") && !id.contains("\\") && !id.unicodeScalars.contains { $0.value < 32 }
    }

    private static func boundedFile(_ file: URL) throws -> Data? {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        else { return nil }
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumMetadataBytes else { return nil }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumMetadataBytes + 1) ?? Data()
        return data.count <= maximumMetadataBytes ? data : nil
    }

    /// Read only ImageIO metadata, never decode or re-encode the retained image.
    private static func imagePixelSize(_ file: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = values[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = values[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue.isFinite, height.doubleValue.isFinite,
              width.doubleValue > 0, height.doubleValue > 0 else { return nil }
        let orientation = (values[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation)
            ? CGSize(width: height.doubleValue, height: width.doubleValue)
            : CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private static func isImageFile(_ file: URL) -> Bool {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true && (values.fileSize ?? 0) > 0
    }
}
