import Foundation

/// Turns one page of a pixiv work into a wallpaper in the library, packaged as a
/// `StillImageWallpaper`: the original image beside a small page that shows it, with an Image
/// fit property the inspector edits.
actor PixivWallpaperPackager {
    /// The formats pixiv serves originals in, recognised by their first bytes rather than by
    /// the address, so a file is always named after what it really is.
    enum ImageFormat: String, Sendable {
        case jpeg = "jpg", png, gif

        init?(sniffing data: Data) {
            let head = [UInt8](data.prefix(8))
            if head.starts(with: [0xFF, 0xD8, 0xFF]) {
                self = .jpeg
            } else if head.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
                self = .png
            } else if head.starts(with: Array("GIF87a".utf8)) || head.starts(with: Array("GIF89a".utf8)) {
                self = .gif
            } else {
                return nil
            }
        }
    }

    static let stagingPrefix = ".WallpaperMachine-pixiv-"
    static let imageName = "illustration"
    /// Words that already mean something to Installed's filters and must not arrive as tags.
    static let reservedTags: Set<String> = [
        "approved", "everyone", "questionable", "mature", "scene", "video", "web", "application",
        "wallpaper", "preset", "asset",
    ]

    let library: URL
    private let downscale: @Sendable (Data, Int) throws -> Data

    /// `downscale` re-encodes an image as a JPEG no larger than the given pixel size; the app
    /// uses the thumbnail cache's ImageIO encoder, which also proves the bytes decode.
    init(
        library: URL = ClientPaths.libraryURL,
        downscale: @escaping @Sendable (Data, Int) throws -> Data = {
            try WorkshopThumbnailCache.encodeThumbnail($0, maxPixelSize: $1)
        }
    ) {
        self.library = library
        self.downscale = downscale
    }

    /// Writes the project into a staging folder beside the library, then moves it in whole, so
    /// the library never lists a half-written wallpaper. A copy already in the library is kept
    /// as it is, along with the options saved for it. `pageCount` comes from the work's page
    /// list, which is newer than the listing's count. Returns the wallpaper id.
    @discardableResult
    func install(_ image: Data, work: PixivWork, page: PixivPage, pageCount: Int) throws -> String {
        guard let format = ImageFormat(sniffing: image) else { throw PixivFailure(code: .notAnImage) }
        let id = work.libraryID(page: page.index)
        let fm = FileManager.default
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        let root = library.resolvingSymlinksInPath().standardizedFileURL
        let destination = root.appendingPathComponent(id, isDirectory: true)
        if Self.hasManifest(destination) { return id }

        let preview: Data
        var display: Data?
        do {
            preview = try downscale(image, StillImageWallpaper.previewPixels)
            if max(page.width, page.height) > StillImageWallpaper.displayPixels {
                display = try downscale(image, StillImageWallpaper.displayPixels)
            }
        } catch {
            throw PixivFailure(code: .undecodable)
        }
        try Task.checkCancellation()

        let staging = Self.stagingRoot(forLibrary: library)
            .appendingPathComponent(Self.stagingPrefix + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let imageFile = "\(Self.imageName).\(format.rawValue)"
        try image.write(to: staging.appendingPathComponent(imageFile))
        try preview.write(to: staging.appendingPathComponent(StillImageWallpaper.previewFile))
        if let display { try display.write(to: staging.appendingPathComponent(StillImageWallpaper.displayFile)) }
        let fit = StillImageWallpaper.Fit.preferred(width: page.width, height: page.height)
        try Data(StillImageWallpaper.page(showing: display == nil ? imageFile : StillImageWallpaper.displayFile, fit: fit).utf8)
            .write(to: staging.appendingPathComponent(StillImageWallpaper.entryFile))
        let manifest = Self.manifest(work: work, page: page, pageCount: pageCount, imageFile: imageFile, fit: fit)
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: staging.appendingPathComponent("project.json"))
        try Task.checkCancellation()
        do {
            // moveItem never replaces a destination that appeared since the check above.
            try fm.moveItem(at: staging, to: destination)
        } catch {
            // Another download of the same page finished first; its copy stands.
            guard Self.hasManifest(destination) else { throw error }
        }
        return id
    }

    /// Where pages are staged: beside the library as it resolves, so on the same volume, the
    /// final move is a rename, and the library scanner never sees a folder while it is
    /// incomplete. A symlinked library stages beside its target.
    static func stagingRoot(forLibrary library: URL) -> URL {
        library.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent()
    }

    /// A staging folder lives for the moment it takes to write one page; any still there after
    /// `quiet` seconds was left by a crash. Called at launch with `stagingRoot(forLibrary:)`,
    /// before a download can start.
    static func removeAbandonedStaging(in root: URL, quiet: TimeInterval = 600) {
        let fm = FileManager.default
        let deadline = Date().addingTimeInterval(-quiet)
        let entries = (try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]))
            ?? []
        for entry in entries where entry.lastPathComponent.hasPrefix(stagingPrefix) {
            guard let values = try? entry.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                values.isDirectory == true, values.isSymbolicLink != true,
                (values.contentModificationDate ?? .distantFuture) < deadline
            else { continue }
            try? fm.removeItem(at: entry)
        }
    }

    static func hasManifest(_ folder: URL) -> Bool {
        let values = try? folder.appendingPathComponent("project.json")
            .resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true
    }

    /// The manifest the library reads. `pixiv` records where the image came from and who made
    /// it; Wallpaper Engine ignores keys it does not know.
    static func manifest(
        work: PixivWork, page: PixivPage, pageCount: Int, imageFile: String, fit: StillImageWallpaper.Fit
    ) -> [String: Any] {
        let name = work.title.isEmpty ? "pixiv \(work.id)" : work.title
        let title = pageCount > 1 ? "\(name) (\(page.index + 1)/\(pageCount))" : name
        var seen = Set<String>()
        let tags = work.tags.filter {
            let key = $0.lowercased()
            return !reservedTags.contains(key) && seen.insert(key).inserted
        }
        return [
            "title": title,
            "type": "web",
            "file": StillImageWallpaper.entryFile,
            "preview": StillImageWallpaper.previewFile,
            "description": "\(name) by \(work.authorName) on pixiv: \(work.artworkURL.absoluteString)",
            // The library knows three ratings; R-18G is never offered, but would be Mature.
            "contentrating": (work.rating == .grotesque ? PixivRating.mature : work.rating).rawValue,
            "tags": Array(tags.prefix(20)),
            "general": ["properties": StillImageWallpaper.properties(fit: fit)],
            "pixiv": [
                "id": work.id, "page": page.index, "pages": pageCount,
                "author": work.authorName, "authorId": work.authorID,
                "url": work.artworkURL.absoluteString, "original": page.originalURL.absoluteString,
                "file": imageFile, "width": page.width, "height": page.height,
            ],
        ]
    }
}
