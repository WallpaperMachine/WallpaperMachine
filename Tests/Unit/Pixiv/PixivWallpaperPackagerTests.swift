import Foundation
import XCTest

@testable import WallpaperMachine

final class PixivWallpaperPackagerTests: XCTestCase {
    private var root: URL!
    private var library: URL { root.appendingPathComponent("Library", isDirectory: true) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pixiv-packager-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func packager() -> PixivWallpaperPackager {
        PixivWallpaperPackager(library: library) { data, pixels in
            guard PixivWallpaperPackager.ImageFormat(sniffing: data) != nil else {
                throw PixivFailure(code: .undecodable)
            }
            return Data("scaled to \(pixels)".utf8)
        }
    }

    private func work(
        id: String = "150105294", width: Int = 1920, height: Int = 1080, pages: Int = 1,
        rating: PixivRating = .everyone, tags: [String] = ["風景", "sky"]
    ) -> PixivWork {
        PixivWork(
            id: id, title: "Sky", authorID: "17429", authorName: "LAM", thumbnailURL: nil,
            width: width, height: height, pageCount: pages, rating: rating, aiGenerated: false, tags: tags, rank: 1)
    }

    private func page(_ index: Int = 0, width: Int = 1920, height: Int = 1080, file: String = "p0.jpg") -> PixivPage {
        PixivPage(
            index: index, width: width, height: height, previewURL: nil,
            originalURL: URL(string: "https://i.pximg.net/img-original/img/2026/09/26/00/00/50/\(file)")!)
    }

    private func manifest(_ id: String) throws -> [String: Any] {
        let data = try Data(contentsOf: library.appendingPathComponent(id).appendingPathComponent("project.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testInstallWritesAWebProjectTheLibraryCanPlay() async throws {
        let image = PixivFixtures.imageBytes("jpg")

        let id = try await packager().install(image, work: work(rating: .questionable), page: page(), pageCount: 1)

        XCTAssertEqual(id, "pixiv-150105294-p0")
        let folder = library.appendingPathComponent(id)
        let project = try manifest(id)
        XCTAssertEqual(project["type"] as? String, "web")
        XCTAssertEqual(project["file"] as? String, "index.html")
        XCTAssertEqual(project["preview"] as? String, "preview.jpg")
        XCTAssertEqual(project["title"] as? String, "Sky")
        XCTAssertEqual(project["contentrating"] as? String, "Questionable")
        XCTAssertEqual(project["tags"] as? [String], ["風景", "sky"])
        let properties = try XCTUnwrap((project["general"] as? [String: Any])?["properties"] as? [String: Any])
        let fit = try XCTUnwrap(properties["fit"] as? [String: Any])
        XCTAssertEqual(fit["type"] as? String, "combo")
        XCTAssertEqual(fit["value"] as? String, "fill", "a wide image fills the screen")
        XCTAssertEqual(
            (fit["options"] as? [[String: Any]])?.compactMap { $0["value"] as? String },
            ["fill", "fill-top", "blur", "fit", "center"])
        XCTAssertEqual((properties["background"] as? [String: Any])?["type"] as? String, "color")
        let source = try XCTUnwrap(project["pixiv"] as? [String: Any])
        XCTAssertEqual(source["url"] as? String, "https://www.pixiv.net/artworks/150105294")
        XCTAssertEqual(source["author"] as? String, "LAM")

        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("illustration.jpg")), image)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("preview.jpg")), Data("scaled to 512".utf8))
        let page = try String(contentsOf: folder.appendingPathComponent("index.html"), encoding: .utf8)
        XCTAssertTrue(page.contains(#"src="illustration.jpg""#))
        XCTAssertTrue(page.contains(#"data-fit="fill""#))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("display.jpg").path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["Library"],
            "no staging folder is left beside the library")
    }

    func testTallPagesAreShownWholeAndNamedAfterTheirPage() async throws {
        let png = PixivFixtures.imageBytes("png")

        let id = try await packager().install(
            png, work: work(width: 1360, height: 1920, pages: 1), page: page(2, width: 1360, height: 1920),
            pageCount: 5)

        XCTAssertEqual(id, "pixiv-150105294-p2")
        let project = try manifest(id)
        XCTAssertEqual(project["title"] as? String, "Sky (3/5)")
        let properties = (project["general"] as? [String: Any])?["properties"] as? [String: Any]
        XCTAssertEqual((properties?["fit"] as? [String: Any])?["value"] as? String, "blur")
        let folder = library.appendingPathComponent(id)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("illustration.png")), png,
                       "the file is named for what its bytes are, not for its address")
        let html = try String(contentsOf: folder.appendingPathComponent("index.html"), encoding: .utf8)
        XCTAssertTrue(html.contains(#"src="illustration.png""#))
    }

    func testHugeOriginalsAreShownFromAScaledCopy() async throws {
        let id = try await packager().install(
            PixivFixtures.imageBytes("jpg"), work: work(width: 9000, height: 6000), page: page(width: 9000, height: 6000),
            pageCount: 1)

        let folder = library.appendingPathComponent(id)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("display.jpg")), Data("scaled to 8192".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("illustration.jpg").path))
        let html = try String(contentsOf: folder.appendingPathComponent("index.html"), encoding: .utf8)
        XCTAssertTrue(html.contains(#"src="display.jpg""#))
        XCTAssertFalse(html.contains(#"src="illustration.jpg""#))
    }

    func testAnExistingCopyAndItsFilesAreKept() async throws {
        let folder = library.appendingPathComponent("pixiv-150105294-p0")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"type":"web","file":"index.html","title":"Mine"}"#.utf8)
            .write(to: folder.appendingPathComponent("project.json"))

        let id = try await packager().install(PixivFixtures.imageBytes("jpg"), work: work(), page: page(), pageCount: 1)

        XCTAssertEqual(id, "pixiv-150105294-p0")
        XCTAssertEqual(try manifest(id)["title"] as? String, "Mine")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["project.json"])
    }

    func testFilesThatAreNotImagesNeverReachTheLibrary() async throws {
        let packager = packager()
        await XCTAssertPixivFailure(
            try await packager.install(Data("<html>".utf8), work: work(), page: page(), pageCount: 1), .notAnImage)
        let broken = PixivWallpaperPackager(library: library) { _, _ in throw CocoaError(.fileReadCorruptFile) }
        await XCTAssertPixivFailure(
            try await broken.install(PixivFixtures.imageBytes("gif"), work: work(), page: page(), pageCount: 1),
            .undecodable)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Library"])
    }

    func testTagsThatMeanSomethingToInstalledFiltersAreLeftOut() async throws {
        let id = try await packager().install(
            PixivFixtures.imageBytes("jpg"),
            work: work(tags: ["Approved", "Mature", "風景", "SKY", "sky", "Video"]), page: page(), pageCount: 1)

        XCTAssertEqual(try manifest(id)["tags"] as? [String], ["風景", "SKY"])
    }

    func testLaunchRemovesOnlyStagingACrashLeftBehind() throws {
        let fm = FileManager.default
        let abandoned = root.appendingPathComponent(PixivWallpaperPackager.stagingPrefix + "old")
        let fresh = root.appendingPathComponent(PixivWallpaperPackager.stagingPrefix + "new")
        let unrelated = root.appendingPathComponent(".WallpaperMachine-import-old")
        for folder in [abandoned, fresh, unrelated] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: folder.appendingPathComponent("illustration.jpg"))
        }
        let hourAgo = Date().addingTimeInterval(-3600)
        for folder in [abandoned, unrelated] {
            try fm.setAttributes([.modificationDate: hourAgo], ofItemAtPath: folder.path)
        }

        PixivWallpaperPackager.removeAbandonedStaging(in: root)

        XCTAssertFalse(fm.fileExists(atPath: abandoned.path))
        XCTAssertTrue(fm.fileExists(atPath: fresh.path), "a page being written right now is left alone")
        XCTAssertTrue(fm.fileExists(atPath: unrelated.path))
    }

    func testImageFormatsAreRecognisedByTheirSignature() {
        typealias Format = PixivWallpaperPackager.ImageFormat
        XCTAssertEqual(Format(sniffing: PixivFixtures.imageBytes("jpg")), .jpeg)
        XCTAssertEqual(Format(sniffing: PixivFixtures.imageBytes("png")), .png)
        XCTAssertEqual(Format(sniffing: PixivFixtures.imageBytes("gif")), .gif)
        XCTAssertEqual(Format(sniffing: Data("GIF87a...".utf8)), .gif)
        XCTAssertNil(Format(sniffing: Data("RIFF....WEBP".utf8)))
        XCTAssertNil(Format(sniffing: Data()))
    }
}
