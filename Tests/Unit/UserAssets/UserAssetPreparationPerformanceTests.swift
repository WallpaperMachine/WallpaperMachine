import XCTest
@testable import WallpaperMachine

/// Observations, not timing gates: machine load changes latency, while the
/// assertions cover complete preparation and an unchanged warm bridge.
@MainActor
final class UserAssetPreparationPerformanceTests: XCTestCase {
    func testSyntheticDirectoryPreparationAndMainActorLatency() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("asset-preparation-measurement-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var measurements: [[String: Any]] = []
        for count in [8, 128, 1024] {
            let directory = root.appendingPathComponent("source-\(count)")
            let project = root.appendingPathComponent("project-\(count)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            for index in 0..<count {
                var bytes = Data(repeating: UInt8(index % 251), count: 4096)
                bytes.append(contentsOf: String(index).utf8)
                try bytes.write(to: directory.appendingPathComponent("image-\(index).png"))
            }
            let store = UserAssetStore(projectURL: project, wallpaperId: String(count),
                managed: ManagedUserAssetStore(root: root.appendingPathComponent("managed")),
                watcherFactory: { _, _ in MeasurementDirectoryWatcher() })
            var firstInode: NSNumber?
            for pass in ["cold", "warm"] {
                let samples = LatencySamples()
                let probing = expectation(description: "latency sampler ready")
                let probe = Task.detached {
                    let scheduled = ContinuousClock.now
                    await MainActor.run { samples.values.append(Self.seconds(scheduled.duration(to: .now))) }
                    probing.fulfill()
                    while !Task.isCancelled {
                        let scheduled = ContinuousClock.now
                        await MainActor.run { samples.values.append(Self.seconds(scheduled.duration(to: .now))) }
                        try? await Task.sleep(for: .milliseconds(1))
                    }
                }
                await fulfillment(of: [probing], timeout: 5)
                let start = ContinuousClock.now
                let files: [UserAssetImport]
                do {
                    files = try await store.importDirectory(at: directory, propertyId: "gallery", filter: .image, limit: 4096)
                } catch {
                    probe.cancel()
                    await probe.value
                    throw error
                }
                let elapsed = Self.seconds(start.duration(to: .now))
                probe.cancel()
                await probe.value
                XCTAssertEqual(files.count, count)
                XCTAssertEqual(store.stagedFiles(propertyId: "gallery").count, count)
                XCTAssertFalse(samples.values.isEmpty)
                let path = try XCTUnwrap(files.first?.stagedPath)
                let inode = try FileManager.default.attributesOfItem(atPath: path)[.systemFileNumber] as? NSNumber
                if pass == "cold" { firstInode = inode }
                else { XCTAssertEqual(inode, firstInode, "An unchanged warm preparation must reuse the bridge file") }
                measurements.append([
                    "files": count, "pass": pass, "preparation_ms": elapsed * 1000,
                    "main_actor_samples": samples.values.count,
                    "main_actor_max_delay_ms": (samples.values.max() ?? 0) * 1000,
                    "main_actor_mean_delay_ms": samples.values.reduce(0, +) / Double(max(1, samples.values.count)) * 1000,
                ])
            }
            store.cancelImports()
        }
        let data = try JSONSerialization.data(withJSONObject: measurements, options: [.sortedKeys])
        let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        evidence.name = "Synthetic user-asset preparation and main-actor latency"
        evidence.lifetime = .keepAlways
        add(evidence)
        print("USER_ASSET_PREPARATION_METRICS \(String(decoding: data, as: UTF8.self))")
    }

    @MainActor private final class LatencySamples { var values: [Double] = [] }

    private final class MeasurementDirectoryWatcher: DirectoryWatching {
        func stop() {}
    }

    nonisolated private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
