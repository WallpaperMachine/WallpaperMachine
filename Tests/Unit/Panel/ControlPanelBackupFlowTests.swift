import Foundation
import XCTest

@testable import WallpaperMachine

@MainActor
final class ControlPanelBackupFlowTests: ControlPanelTestCase {
  func testLibraryInclusionAndReplaceChoiceProduceTheRequestedPendingRestore() async throws {
    try await withPanel { panel in
      let project = panel.library.appendingPathComponent("101", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      let original = Data("<!doctype html><html><body>Original</body></html>".utf8)
      try original.write(to: project.appendingPathComponent("index.html"))
      try Data(#"{"type":"web","title":"Original","file":"index.html"}"#.utf8)
        .write(to: project.appendingPathComponent("project.json"))
      try "schema_version = 1\n".write(to: panel.root.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
      let exports = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: exports) }
      let package = exports.appendingPathComponent("Library.wmbackup")
      panel.pickers.exportBackup = { package }
      panel.pickers.restoreBackup = { package }
      try await panel.finishWelcome()
      panel.navigation.selection = .settings
      panel.show()
      try await panel.waitJS("powerProbe.received.at(-1)?.page === 'settings'")
      _ = try await panel.js("document.querySelector('[data-section=\"storage\"]').click()")
      try await panel.waitJS("Boolean(document.getElementById('settings-control-backup-include-library'))")
      _ = try await panel.js("""
        document.getElementById('settings-control-backup-include-library').click();
        document.querySelector('[data-key="backup-export"] [data-action="backupExport"]').click();
        """)
      try await panel.waitUntil(timeout: 10) { panel.backup.status != nil || panel.backup.error != nil }
      try await panel.waitUntil(timeout: 10) { !panel.backup.busy }
      XCTAssertNil(panel.backup.error)
      XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent("data/Library/101/index.html")), original)
      let current = Data("<!doctype html><html><body>Changed locally</body></html>".utf8)
      try current.write(to: project.appendingPathComponent("index.html"))
      _ = try await panel.js("document.querySelector('[data-key=\"backup-restore\"] [data-action=\"backupPreview\"]').click()")
      try await panel.waitUntil(timeout: 10) { panel.backup.preview != nil || panel.backup.error != nil }
      XCTAssertNil(panel.backup.error)
      let preview = try XCTUnwrap(panel.backup.preview)
      XCTAssertTrue(preview.conflicts.contains("Library/101"))
      try await panel.waitJS("Boolean(document.querySelector('input[name=\"backup-conflict\"][value=\"replace\"]'))")
      _ = try await panel.js("""
        document.querySelector('input[name="backup-conflict"][value="replace"]').click();
        document.querySelector('[data-key="backup-restore-actions"] [data-action="backupRestore"]').click();
        """)
      try await panel.waitUntil(timeout: 10) { panel.backup.pendingRestore || panel.backup.error != nil }
      XCTAssertNil(panel.backup.error)
      let pending = panel.root.appendingPathComponent(WallpaperBackupService.pendingDirectoryName)
      let state = try JSONDecoder().decode(WallpaperBackupPending.self,
        from: Data(contentsOf: pending.appendingPathComponent("pending.json")))
      XCTAssertEqual(state.policy, .replace)
      XCTAssertEqual(try Data(contentsOf: pending.appendingPathComponent("data/Library/101/index.html")), original)
      XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("index.html")), current)
      try await panel.waitJS("Boolean(document.querySelector('[data-action=\"backupCancelRestore\"]'))")
      _ = try await panel.js("document.querySelector('[data-action=\"backupCancelRestore\"]').click()")
      try await panel.waitUntil(timeout: 5) { !panel.backup.pendingRestore }
      XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
      XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("index.html")), current)
    }
  }
}
