import Foundation

/// Turns one page of a pixiv work into a wallpaper in the library. The renderer plays scene,
/// video and web projects only, so an illustration is saved as a `web` project: the original
/// image beside a small page that shows it, with an Image fit property the inspector edits.
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

    /// How the page meets the screen; the values of the manifest's `fit` combo.
    enum Fit: String, CaseIterable, Sendable {
        case fill, fillTop = "fill-top", blur, fit, center

        /// The option's label in the manifest. It stays English there, like every property
        /// label a wallpaper ships, and the panel translates these few.
        var label: String {
            switch self {
            case .fill: "Fill"
            case .fillTop: "Fill, keep the top"
            case .blur: "Fit with blurred backdrop"
            case .fit: "Fit"
            case .center: "Original size"
            }
        }

        /// Wide images fill the screen; anything squarer or taller is shown whole over a
        /// blurred copy of itself instead of losing most of its height.
        static func preferred(width: Int, height: Int) -> Fit {
            width * 5 >= height * 6 ? .fill : .blur
        }
    }

    static let stagingPrefix = ".WallpaperMachine-pixiv-"
    static let entryFile = "index.html"
    static let previewFile = "preview.jpg"
    static let imageName = "illustration"
    static let displayFile = "display.jpg"
    static let previewPixels = 512
    /// A web view decodes the whole image, so an original larger than this on its long side is
    /// shown from a scaled copy and kept alongside it untouched.
    static let displayPixels = 8192
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
            preview = try downscale(image, Self.previewPixels)
            if max(page.width, page.height) > Self.displayPixels {
                display = try downscale(image, Self.displayPixels)
            }
        } catch {
            throw PixivFailure(code: .undecodable)
        }
        try Task.checkCancellation()

        // A sibling of the library is on the same volume, so the final move is a rename, and
        // the library scanner never sees the folder while it is incomplete.
        let staging = root.deletingLastPathComponent()
            .appendingPathComponent(Self.stagingPrefix + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let imageFile = "\(Self.imageName).\(format.rawValue)"
        try image.write(to: staging.appendingPathComponent(imageFile))
        try preview.write(to: staging.appendingPathComponent(Self.previewFile))
        if let display { try display.write(to: staging.appendingPathComponent(Self.displayFile)) }
        let fit = Fit.preferred(width: page.width, height: page.height)
        try Data(Self.page(showing: display == nil ? imageFile : Self.displayFile, fit: fit).utf8)
            .write(to: staging.appendingPathComponent(Self.entryFile))
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

    /// A staging folder lives for the moment it takes to write one page; any still there after
    /// `quiet` seconds was left by a crash. Called at launch, before a download can start.
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
        work: PixivWork, page: PixivPage, pageCount: Int, imageFile: String, fit: Fit
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
            "file": entryFile,
            "preview": previewFile,
            "description": "\(name) by \(work.authorName) on pixiv: \(work.artworkURL.absoluteString)",
            // The library knows three ratings; R-18G is never offered, but would be Mature.
            "contentrating": (work.rating == .grotesque ? PixivRating.mature : work.rating).rawValue,
            "tags": Array(tags.prefix(20)),
            "general": [
                "properties": [
                    "fit": [
                        "order": 0, "text": "Image fit", "type": "combo", "value": fit.rawValue,
                        "options": Fit.allCases.map { ["label": $0.label, "value": $0.rawValue] },
                    ],
                    "background": [
                        "order": 1, "text": "Background color", "type": "color", "value": "0 0 0",
                    ],
                ]
            ],
            "pixiv": [
                "id": work.id, "page": page.index, "pages": pageCount,
                "author": work.authorName, "authorId": work.authorID,
                "url": work.artworkURL.absoluteString, "original": page.originalURL.absoluteString,
                "file": imageFile, "width": page.width, "height": page.height,
            ],
        ]
    }

    /// The wallpaper page. It holds no text from pixiv; the only name in it is the image file
    /// this packager chose. The host replays `applyUserProperties` to a listener registered
    /// after load, and `data-fit` covers the first paint before that.
    static func page(showing file: String, fit: Fit) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>pixiv illustration</title>
        <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: #000; }
        img { position: fixed; display: block; }
        #art { inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: 50% 50%; }
        #backdrop { display: none; inset: -8vmax; width: calc(100% + 16vmax); height: calc(100% + 16vmax); object-fit: cover; filter: blur(5vmax) brightness(0.72); }
        body[data-fit="fill-top"] #art { object-position: 50% 0; }
        body[data-fit="blur"] #art, body[data-fit="fit"] #art { object-fit: contain; }
        body[data-fit="blur"] #backdrop { display: block; }
        body[data-fit="center"] #art { object-fit: none; }
        </style>
        </head>
        <body data-fit="\(fit.rawValue)">
        <img id="backdrop" src="\(file)" alt="">
        <img id="art" src="\(file)" alt="">
        <script>
        (() => {
          const fits = new Set(\(fitList));
          window.wallpaperPropertyListener = {
            applyUserProperties(properties) {
              const fit = properties.fit && String(properties.fit.value);
              if (fits.has(fit)) document.body.dataset.fit = fit;
              const rgb = properties.background && String(properties.background.value).trim().split(/\\s+/).map(Number);
              if (rgb && rgb.length === 3 && rgb.every(Number.isFinite)) {
                document.body.style.background = `rgb(${rgb.map(part => Math.round(Math.min(1, Math.max(0, part)) * 255)).join(', ')})`;
              }
            },
          };
        })();
        </script>
        </body>
        </html>

        """
    }

    private static var fitList: String {
        "[" + Fit.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ") + "]"
    }
}
