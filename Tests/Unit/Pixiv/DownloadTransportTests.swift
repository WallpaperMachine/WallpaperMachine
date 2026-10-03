import Foundation
import XCTest

@testable import WallpaperMachine

final class DownloadTransportTests: XCTestCase {
    func testThumbnailStreamChecksDeclaredUnknownAndExactLengths() async throws {
        for (headers, size, succeeds) in [(["Content-Length": "32"], 4, false), ([:], 17, false), (["Content-Length": "16"], 16, true)] {
            let fixture = TransferFixture([.init(headers: headers, body: Data(repeating: 1, count: size))])
            defer { fixture.close() }
            do {
                let result = try await URLSessionThumbnailFetcher(session: fixture.session, byteLimit: 16).fetch(fixture.url)
                XCTAssertTrue(succeeds)
                XCTAssertEqual(result.count, 16)
            } catch let failure as WorkshopThumbnailFailure {
                XCTAssertFalse(succeeds)
                XCTAssertEqual(failure.code, .tooLarge)
            }
        }
    }

    func testThumbnailCancellationStopsItsTransport() async throws {
        let fixture = TransferFixture([.init(body: Data([1, 2, 3]), holdsOpen: true)])
        defer { fixture.close() }
        let task = Task { try await URLSessionThumbnailFetcher(session: fixture.session, byteLimit: 16).fetch(fixture.url) }
        try await waitUntil { fixture.state.requests.count == 1 }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled request finished") } catch {}
        try await waitUntil { fixture.state.stopped > 0 }
    }

    func testPixivContinuesTheSameRepresentationWithRangeAfterCancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pixiv-range-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = Data(repeating: 65, count: 65_536)
        let suffix = Data(repeating: 66, count: 65_536)
        let fixture = TransferFixture([
            .init(headers: ["Content-Length": "131072", "ETag": "\"first\""], body: prefix, holdsOpen: true),
            .init(status: 206, headers: ["Content-Length": "65536", "Content-Range": "bytes 65536-131071/131072", "ETag": "\"first\""], body: suffix),
        ])
        defer { fixture.close() }
        let transport = URLSessionPixivTransport(session: fixture.session)
        let first = Task { try await transport.image(from: fixture.url, limit: 131_072, checkpoint: root) { _, _ in } }
        // URLProtocol buffers very short unfinished bodies; one ordinary 64 KiB image chunk
        // exercises actual AsyncBytes delivery and provides a deterministic pause boundary.
        try await waitUntil {
            let attributes = try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("image.partial").path)
            return (attributes?[.size] as? NSNumber)?.intValue == prefix.count
        }
        first.cancel()
        do { _ = try await first.value; XCTFail("cancelled request finished") } catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("image.partial")), prefix)
        let result = try await transport.image(from: fixture.url, limit: 131_072, checkpoint: root) { _, _ in }
        XCTAssertEqual(result, prefix + suffix)
        XCTAssertEqual(fixture.state.requests.last?.value(forHTTPHeaderField: "Range"), "bytes=65536-")
        XCTAssertEqual(fixture.state.requests.last?.value(forHTTPHeaderField: "If-Range"), "\"first\"")
    }

    func testPixivChangedRepresentationReplacesRatherThanAppendsPartialBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pixiv-changed-range-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = TransferFixture([.init(headers: ["Content-Length": "4", "ETag": "\"new\""], body: Data("WXYZ".utf8))])
        defer { fixture.close() }
        try Data("old".utf8).write(to: root.appendingPathComponent("image.partial"))
        try JSONSerialization.data(withJSONObject: ["url": fixture.url.absoluteString, "validator": "\"old\"", "expected": 8])
            .write(to: root.appendingPathComponent("transfer.json"))
        let result = try await URLSessionPixivTransport(session: fixture.session)
            .image(from: fixture.url, limit: 16, checkpoint: root) { _, _ in }
        XCTAssertEqual(result, Data("WXYZ".utf8))
        XCTAssertEqual(fixture.state.requests.first?.value(forHTTPHeaderField: "Range"), "bytes=3-")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("image.partial")), result)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private final class TransferFixture: @unchecked Sendable {
    struct Response: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var holdsOpen = false
    }
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [Response]
        private var seen: [URLRequest] = []
        private var stops = 0
        init(_ responses: [Response]) { self.responses = responses }
        var requests: [URLRequest] { lock.withLock { seen } }
        var stopped: Int { lock.withLock { stops } }
        func next(_ request: URLRequest) -> Response? {
            lock.withLock {
                seen.append(request)
                return responses.isEmpty ? nil : responses.removeFirst()
            }
        }
        func stop() { lock.withLock { stops += 1 } }
    }
    let state: State
    let session: URLSession
    let url: URL
    init(_ responses: [Response]) {
        state = State(responses)
        url = URL(string: "https://\(UUID().uuidString.lowercased()).invalid/image")!
        TransferProtocol.register(state, host: url.host!)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransferProtocol.self]
        session = URLSession(configuration: configuration)
    }
    func close() {
        session.invalidateAndCancel()
        TransferProtocol.remove(host: url.host!)
    }
}

private final class TransferProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var registry: [String: TransferFixture.State] = [:]
    private var state: TransferFixture.State?
    static func register(_ state: TransferFixture.State, host: String) { lock.withLock { registry[host] = state } }
    static func remove(host: String) { _ = lock.withLock { registry.removeValue(forKey: host) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        state = Self.lock.withLock { Self.registry[request.url?.host ?? ""] }
        guard let response = state?.next(request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        if !response.holdsOpen { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { state?.stop() }
}
