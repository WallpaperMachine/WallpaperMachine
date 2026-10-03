import Darwin
import XCTest

@testable import WallpaperMachine

final class WallpaperImportStagingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("import-staging-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func directory() throws -> URL {
        let directory = root.appendingPathComponent(WallpaperImportService.stagingPrefix + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    func testLiveClaimProtectsAnImportAndReleasedClaimIsReclaimed() throws {
        let staging = try directory()
        var claim = try WallpaperImportService.claimStaging(staging)
        defer { if claim >= 0 { close(claim) } }
        let asset = staging.appendingPathComponent("copied.png")
        try Data("partial copy".utf8).write(to: asset)
        WallpaperImportService.removeAbandonedStaging(in: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        close(claim)
        claim = -1
        WallpaperImportService.removeAbandonedStaging(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func testLegacySweepRequiresTheWholeTreeToBeQuiet() throws {
        let staging = try directory()
        let asset = staging.appendingPathComponent("recent-copy.png")
        try Data("partial copy".utf8).write(to: asset)
        let old = Date().addingTimeInterval(-172_800)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: staging.path)
        WallpaperImportService.removeAbandonedStaging(in: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: asset.path)
        WallpaperImportService.removeAbandonedStaging(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func testUnknownClaimsAndUnrelatedDirectoriesAreRetained() throws {
        let staging = try directory()
        try Data("future owner format".utf8).write(to: staging.appendingPathComponent(WallpaperImportService.stagingOwnerName))
        let unrelated = root.appendingPathComponent("my-original-wallpaper")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let linked = root.appendingPathComponent(WallpaperImportService.stagingPrefix + UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: unrelated)
        WallpaperImportService.removeAbandonedStaging(in: root, legacyQuietFor: 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertNotNil(try FileManager.default.attributesOfItem(atPath: linked.path)[.type])
    }

    @MainActor
    func testShutdownWaitsForCancelledImportStagingToDisappear() async throws {
        let source = root.appendingPathComponent("wallpaper.html")
        try Data("<!doctype html><title>fixture</title>".utf8).write(to: source)
        let store = LibraryImportStore(library: root.appendingPathComponent("Library"))
        try store.start([source], duplicates: .skip)
        await store.shutdown()
        XCTAssertFalse(store.isBusy)
        XCTAssertTrue(store.report?.cancelled == true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(WallpaperImportService.stagingPrefix) }.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), Data("<!doctype html><title>fixture</title>".utf8))
    }

    func testSymlinkedLibraryUsesItsActualParentForStaging() throws {
        let target = root.appendingPathComponent("elsewhere/Library")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let library = root.appendingPathComponent("Library")
        try FileManager.default.createSymbolicLink(at: library, withDestinationURL: target)
        XCTAssertEqual(WallpaperImportService.stagingRoot(forLibrary: library),
                       target.deletingLastPathComponent().resolvingSymlinksInPath())
    }
}
