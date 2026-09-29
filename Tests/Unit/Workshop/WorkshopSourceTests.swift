import XCTest

@testable import WallpaperMachine

/// Discover's other sources: an author's wallpapers, collections and the signed-in account's
/// subscriptions. Steam is answered by a fixture protocol, so nothing reaches the network.
@MainActor
final class WorkshopSourceTests: XCTestCase {
  private static let author = "76561198000000001"
  private var fixture: SourceFixture!

  override func setUpWithError() throws {
    fixture = try SourceFixture()
  }

  override func tearDown() {
    fixture?.remove()
    fixture = nil
  }

  // MARK: Session

  func testSteamSessionIsReadFromSteamsCookieOnly() {
    let token = "eyJhbGciOiJFZERTQSJ9.payload-part_1"
    let raw = SteamWebSession(cookie: "\(Self.author)||\(token)")
    XCTAssertEqual(raw?.steamID, Self.author)
    XCTAssertEqual(raw?.cookie, "\(Self.author)||\(token)")
    // Steam percent-encodes the bars in the cookie it sets; the value is sent back as it came.
    let encoded = SteamWebSession(cookie: "\(Self.author)%7C%7C\(token)")
    XCTAssertEqual(encoded?.steamID, Self.author)
    XCTAssertEqual(encoded?.cookie, "\(Self.author)%7C%7C\(token)")
    for value in [
      "", token, "\(Self.author)||", "7656119800000000||\(token)", "\(Self.author)||short",
      "\(Self.author)||\(token); Path=/", "\(Self.author)||\(token)||more", "x\(Self.author.dropFirst())||\(token)",
    ] {
      XCTAssertNil(SteamWebSession(cookie: value), value)
    }
  }

  // MARK: Decoding

  func testProfileListingReadsItsItemsTotalAndOwner() throws {
    let listing = try WorkshopService.decodeProfileListing(String(
      decoding: profileHTML(ids: ["300", "100", "300", "200"], name: "Night &amp; Day", total: "1,147"),
      as: UTF8.self))
    XCTAssertEqual(listing.ids, ["300", "100", "200"])
    XCTAssertEqual(listing.total, 1147)
    XCTAssertEqual(listing.name, "Night & Day")
  }

  /// Every Steam page links to the sign-in page from its header, so only a page titled so means
  /// the session is gone; an author with nothing published is simply empty.
  func testOnlySteamsSignInPageMeansSigningInAgain() throws {
    XCTAssertThrowsError(try WorkshopService.decodeProfileListing(
      "<html><head><title>Sign In</title></head><a href=\"https://steamcommunity.com/login/home/\">Sign in</a></html>"
    )) { XCTAssertTrue($0 is SteamSignInRequired) }
    let empty = try WorkshopService.decodeProfileListing(
      "<html><head><title>Steam Community :: Rabscuttle</title></head><a href=\"https://steamcommunity.com/login/home/?goto=\">Sign in</a></html>")
    XCTAssertEqual(empty.ids, [])
    XCTAssertEqual(empty.total, 0)
    XCTAssertEqual(empty.name, "Rabscuttle")
  }

  func testCollectionIsListedInItsOwnOrderAndAGoneOneSaysSo() throws {
    let ids = try WorkshopService.decodeCollection(collectionJSON(children: [("30", 2), ("10", 0), ("20", 1)]))
    XCTAssertEqual(ids, ["10", "20", "30"])
    XCTAssertThrowsError(try WorkshopService.decodeCollection(
      Data(#"{"response":{"result":1,"resultcount":1,"collectiondetails":[{"publishedfileid":"9","result":9}]}}"#.utf8)))
  }

  func testBrowsedCollectionsAreMarkedWithTheWallpapersTheyHold() throws {
    let browse = try WorkshopService.decodeBrowse(String(decoding: browseHTML(rows: [
      collectionRow("900", children: [("12", 1, 0), ("11", 0, 0), ("950", 2, 2)]),
      wallpaperRow("12", tags: ["Scene"]),
    ]), as: UTF8.self))
    XCTAssertEqual(browse.page.items.map(\.collectionSize), [3, nil])
    // A collection inside the collection is not a wallpaper to vouch for it.
    XCTAssertEqual(browse.children["900"], ["11", "12"])
    XCTAssertEqual(browse.page.items.first?.creatorID, Self.author)
  }

  /// A page of collections carries every collection's children, over a megabyte of page data.
  func testAPageOfAMegabyteOrMoreIsStillRead() throws {
    var rows = (1...30).map { collectionRow(String(900 + $0), children: (1...40).map { (String(5000 + $0), $0, 0) }) }
    for index in rows.indices { rows[index]["short_description"] = String(repeating: "\"quoted\" \\ text ", count: 2400) }
    let html = browseHTML(rows: rows)
    XCTAssertGreaterThan(html.count, 1_000_000)
    let browse = try WorkshopService.decodeBrowse(String(decoding: html, as: UTF8.self))
    XCTAssertEqual(browse.page.items.count, 30)
    XCTAssertEqual(browse.children["901"]?.count, 40)
  }

  func testDetailsMarkCollectionsMadeBySteamsCollectionApp() throws {
    var row = detailsRow("5", tags: [])
    row["creator_app_id"] = WorkshopService.collectionCreatorApp
    XCTAssertEqual(WorkshopService.item(details: row)?.collectionSize, 0)
    XCTAssertNil(WorkshopService.item(details: detailsRow("6", tags: []))?.collectionSize)
  }

  func testUnfilteredSourcesFollowTheSidebarsRules() {
    let page = WorkshopPage(
      items: [
        item("1", tags: ["Scene", "Anime", "Everyone"]),
        item("2", tags: ["scene", "Mature"]),
        item("3", tags: ["Video", "Everyone"]),
        item("4", tags: ["Scene", "Everyone"], collection: true),
      ], page: 1, totalPages: 1, totalCount: 4)
    XCTAssertEqual(WorkshopService.matching(page, tags: ["Scene"], excludedTags: ["mature"]).items.map(\.id), ["1"])
    // Only a hidden rating makes an unvouched collection unsafe to show.
    XCTAssertEqual(WorkshopService.matching(page, tags: [], excludedTags: ["Anime"]).items.map(\.id), ["2", "3", "4"])
    // A tag both required and excluded is required, as it is on Steam.
    XCTAssertEqual(WorkshopService.matching(page, tags: ["Mature"], excludedTags: ["Mature"]).items.map(\.id), ["2"])
    XCTAssertEqual(WorkshopService.matching(page, tags: [], excludedTags: []).totalCount, 4)
  }

  // MARK: Fetching

  /// Collections carry no rating of their own: while one is hidden, a collection is shown only
  /// when its first wallpapers all carry none of the hidden tags.
  func testCollectionsWhoseWallpapersCarryAHiddenRatingAreNotShown() async throws {
    fixture.browse = browseHTML(rows: [
      collectionRow("901", children: [("1", 0, 0), ("2", 0, 1)]),
      collectionRow("902", children: [("3", 0, 0), ("4", 0, 1)]),
      collectionRow("903", children: []),
      collectionRow("904", children: [("5", 0, 0)], tags: ["Mature"]),
    ])
    fixture.details = [
      "1": detailsRow("1", tags: ["Scene", "Everyone"]), "2": detailsRow("2", tags: ["Video", "Everyone"]),
      "3": detailsRow("3", tags: ["Scene", "Everyone"]), "4": detailsRow("4", tags: ["Scene", "Mature"]),
      "5": detailsRow("5", tags: ["Scene", "Everyone"]),
    ]
    let screened = try await fixture.service.collections(
      search: "", sort: .topRated, page: 1, tags: [], excludedTags: WorkshopStore.defaultExcludedTags)
    XCTAssertEqual(screened.items.map(\.id), ["901"])
    XCTAssertEqual(fixture.browseSections, ["collections"])

    let open = try await fixture.service.collections(
      search: "", sort: .topRated, page: 1, tags: [], excludedTags: ["Application"])
    XCTAssertEqual(open.items.map(\.id), ["901", "902", "903", "904"])
    XCTAssertEqual(fixture.detailsRequests, 1, "Nothing is sampled while every rating is shown")
  }

  func testCollectionPagesHoldItsItemsThirtyAtATime() async throws {
    let children = (1...35).map { (String(1000 + $0), $0) }
    fixture.collection = collectionJSON(children: children)
    fixture.details = Dictionary(uniqueKeysWithValues: children.map { ($0.0, detailsRow($0.0, tags: ["Scene", "Everyone"])) })
    let first = try await fixture.service.collectionPage(id: "77", page: 1, tags: [], excludedTags: [])
    XCTAssertEqual(first.items.count, 30)
    XCTAssertEqual(first.items.first?.id, "1001")
    XCTAssertEqual(first.totalPages, 2)
    XCTAssertEqual(first.totalCount, 35)
    let second = try await fixture.service.collectionPage(id: "77", page: 2, tags: [], excludedTags: [])
    XCTAssertEqual(second.items.map(\.id), ["1031", "1032", "1033", "1034", "1035"])
  }

  func testAnAuthorsPageIsTitledWithTheirNameAndTheirItemsCarryIt() async throws {
    fixture.profiles[Self.author] = profileHTML(ids: ["1", "2"], name: "Fixture Author", total: "2")
    fixture.details = ["1": detailsRow("1", tags: ["Scene", "Everyone"]), "2": detailsRow("2", tags: ["Scene", "Mature"])]
    var query = WorkshopQuery(text: "", kind: .all, sort: .topRated, excludedTags: ["Mature"])
    query.source = .creator(id: Self.author, name: "Old name")
    let page = try await fixture.service.page(for: query, page: 1, account: nil)
    XCTAssertEqual(page.items.map(\.id), ["1"])
    XCTAssertEqual(page.items.first?.creator, "Fixture Author")
    XCTAssertEqual(page.title, "Fixture Author")
    XCTAssertNil(fixture.cookies.compactMap { $0 }.first, "An author's public page is read without a session")
  }

  func testSubscriptionsAreReadWithTheSessionAndEveryPageOfThem() async throws {
    let session = try XCTUnwrap(SteamWebSession(cookie: "\(Self.author)||0123456789abcdef0123"))
    fixture.subscriptionPages = [
      1: profileHTML(ids: (1...30).map(String.init), name: "Me", total: "32"),
      2: profileHTML(ids: ["31", "32"], name: "Me", total: "32"),
    ]
    let ids = try await fixture.service.subscribedIDs(account: session)
    XCTAssertEqual(ids, (1...32).map(String.init))
    XCTAssertEqual(fixture.cookies, ["steamLoginSecure=\(session.cookie)", "steamLoginSecure=\(session.cookie)"])
  }

  // MARK: Store

  func testOpeningAnAuthorFromACollectionComesBackTheWayItWent() async throws {
    let store = fixture.store
    fixture.browse = browseHTML(rows: [wallpaperRow("12", tags: ["Scene", "Everyone"])])
    fixture.collection = collectionJSON(children: [("12", 0)])
    fixture.details = ["12": detailsRow("12", tags: ["Scene", "Everyone"])]
    fixture.profiles[Self.author] = profileHTML(ids: ["12"], name: "Fixture Author", total: "1")

    store.open(.collections)
    try await finished(store)
    store.open(.collection(id: "77", title: "Night skies"))
    try await finished(store)
    XCTAssertEqual(store.committedQuery?.source, .collection(id: "77", title: "Night skies"))
    store.open(.creator(id: Self.author, name: "Workshop creator"))
    try await finished(store)
    XCTAssertEqual(store.sourceTitle, "Fixture Author")
    XCTAssertEqual(store.sourceHistory, [.collections, .collection(id: "77", title: "Night skies")])

    store.back()
    try await finished(store)
    XCTAssertEqual(store.source, .collection(id: "77", title: "Night skies"))
    store.back()
    try await finished(store)
    XCTAssertEqual(store.source, .collections)
    XCTAssertEqual(store.sourceHistory, [])
    // Choosing a list afresh forgets the way back.
    store.open(.creator(id: Self.author, name: ""))
    try await finished(store)
    store.open(.browse)
    XCTAssertEqual(store.sourceHistory, [])
    try await finished(store)
  }

  func testSubscriptionsWaitForASignInAndAnEndedSessionIsForgotten() async throws {
    let store = fixture.store
    store.open(.subscriptions)
    try await finished(store)
    XCTAssertNotNil(store.errorMessage)
    XCTAssertEqual(store.items, [])

    // A window closed before signing in changes nothing; a cookie that is not a session is refused.
    try await store.signInToSteamWeb { nil }
    XCTAssertNil(store.steamWebSession)
    do {
      try await store.signInToSteamWeb { "not-a-session" }
      XCTFail("A cookie that is not a Steam session must be refused")
    } catch {}
    XCTAssertNil(store.steamWebSession)

    fixture.subscriptionPages = [1: profileHTML(ids: ["1"], name: "Me", total: "1")]
    fixture.details = ["1": detailsRow("1", tags: ["Scene", "Everyone"])]
    try await store.signInToSteamWeb { "\(Self.author)||0123456789abcdef0123" }
    try await finished(store)
    XCTAssertEqual(store.items.map(\.id), ["1"])
    XCTAssertNil(store.errorMessage)

    let missing = try await store.missingSubscriptions(installed: ["1"])
    XCTAssertEqual(missing, [])

    // Steam answers with its sign-in page once the session has ended.
    fixture.subscriptionPages = [1: Data("<html><head><title>Sign In</title></head></html>".utf8)]
    store.search()
    try await finished(store)
    XCTAssertNil(store.steamWebSession)
    XCTAssertEqual(store.errorMessage, SteamSignInRequired().localizedDescription)

    fixture.subscriptionPages = [1: profileHTML(ids: ["1"], name: "Me", total: "1")]
    try await store.signInToSteamWeb { "\(Self.author)||0123456789abcdef0123" }
    try await finished(store)
    store.signOutOfSteamWeb()
    XCTAssertNil(store.steamWebSession)
    XCTAssertEqual(store.items, [])
    XCTAssertFalse(store.hasLoaded)
  }

  // MARK: Fixtures

  private func finished(_ store: WorkshopStore) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    // A load starts on the next turn of the main actor; give it that turn before waiting.
    await Task.yield()
    while store.isLoading {
      guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
      try await Task.sleep(for: .milliseconds(2))
    }
  }

  private func item(_ id: String, tags: [String], collection: Bool = false) -> WorkshopItem {
    WorkshopItem(
      id: id, title: "Item \(id)", creator: "Test", summary: "", previewURL: nil, tags: tags, size: 0,
      subscriptions: 0, collectionSize: collection ? 2 : nil)
  }

  private func profileHTML(ids: [String], name: String, total: String) -> Data {
    let tiles = ids.map { "<div class=\"workshopItem\"><a data-publishedfileid=\"\($0)\"></a></div>" }.joined()
    return Data("""
      <html><head><title>Steam Community :: \(name) :: Workshop Items</title></head>
      <a href="https://steamcommunity.com/login/home/?goto=">Sign in</a>
      <div class="workshopBrowsePagingInfo">Showing 1-\(ids.count) of \(total) entries</div>
      <div class="workshopBrowseItems">\(tiles)</div></html>
      """.utf8)
  }

  private func collectionJSON(children: [(String, Int)]) -> Data {
    let rows = children.map { ["publishedfileid": $0.0, "sortorder": $0.1, "filetype": 0] as [String: Any] }
    let body: [String: Any] = [
      "response": [
        "result": 1, "resultcount": 1,
        "collectiondetails": [["publishedfileid": "77", "result": 1, "children": rows]],
      ]
    ]
    return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
  }

  private func detailsRow(_ id: String, tags: [String]) -> [String: Any] {
    [
      "publishedfileid": id, "result": 1, "consumer_app_id": 431960, "creator_app_id": 431960,
      "title": "Item \(id)", "creator": Self.author, "tags": tags.map { ["tag": $0] },
      "file_size": "2048", "subscriptions": 3, "time_updated": 1_700_000_000,
    ]
  }

  private func wallpaperRow(_ id: String, tags: [String]) -> [String: Any] {
    [
      "publishedfileid": id, "consumer_appid": 431960, "title": "Item \(id)", "creator": Self.author,
      "file_type": 0, "tags": tags.map { ["tag": $0] }, "file_size": "2048",
    ]
  }

  private func collectionRow(
    _ id: String, children: [(String, Int, Int)], tags: [String] = []
  ) -> [String: Any] {
    [
      "publishedfileid": id, "consumer_appid": 431960, "title": "Collection \(id)", "creator": Self.author,
      "file_type": 2, "num_children": children.count, "tags": tags.map { ["tag": $0] },
      "children": children.map { ["publishedfileid": $0.0, "sortorder": $0.1, "file_type": $0.2] },
    ]
  }

  private func browseHTML(rows: [[String: Any]]) -> Data {
    let queries: [[String: Any]] = [
      [
        "queryKey": ["workshop_browse"],
        "state": [
          "data": ["eresult": 1, "current_page": 1, "total_pages": 1, "total_count": rows.count, "results": rows]
        ],
      ]
    ]
    guard let queryData = try? JSONSerialization.data(withJSONObject: ["queries": queries]),
      let context = try? JSONSerialization.data(withJSONObject: ["queryData": String(decoding: queryData, as: UTF8.self)]),
      let encoded = try? JSONSerialization.data(
        withJSONObject: String(decoding: context, as: UTF8.self), options: .fragmentsAllowed)
    else { return Data() }
    return Data(
      "<html><script>window.SSR.renderContext = JSON.parse(\(String(decoding: encoded, as: UTF8.self)));</script></html>".utf8)
  }
}

/// Answers every request of one fixture's session from what the test put there.
@MainActor
private final class SourceFixture {
  let identifier = UUID().uuidString
  let session: URLSession
  let service: WorkshopService
  let store: WorkshopStore
  private let root: URL
  private let defaults: UserDefaults
  private let answers = SourceAnswers()

  var browse: Data {
    get { answers.read { $0.browse } }
    set { answers.write { $0.browse = newValue } }
  }
  var collection: Data {
    get { answers.read { $0.collection } }
    set { answers.write { $0.collection = newValue } }
  }
  var details: [String: [String: Any]] {
    get { answers.read { $0.details } }
    set { answers.write { $0.details = newValue } }
  }
  var profiles: [String: Data] {
    get { answers.read { $0.profiles } }
    set { answers.write { $0.profiles = newValue } }
  }
  var subscriptionPages: [Int: Data] {
    get { answers.read { $0.subscriptionPages } }
    set { answers.write { $0.subscriptionPages = newValue } }
  }
  var browseSections: [String] { answers.read { $0.browseSections } }
  var detailsRequests: Int { answers.read { $0.detailsRequests } }
  var cookies: [String?] { answers.read { $0.cookies } }

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "WorkshopSourceTests-\(identifier)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SourceFixtureProtocol.self]
    configuration.httpAdditionalHeaders = ["X-Source-Test": identifier]
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 5
    session = URLSession(configuration: configuration)
    SourceFixtureProtocol.register(identifier, answers: answers)
    service = WorkshopService(session: session)
    defaults = try XCTUnwrap(UserDefaults(suiteName: "WorkshopSourceTests.\(identifier)"))
    store = WorkshopStore(
      service: service,
      downloader: WorkshopDownloadManager(sessionDirectory: root.appendingPathComponent("SteamSession")),
      supportDirectory: root, defaults: defaults)
  }

  func remove() {
    store.cancelSearch()
    session.invalidateAndCancel()
    SourceFixtureProtocol.remove(identifier)
    defaults.removePersistentDomain(forName: "WorkshopSourceTests.\(identifier)")
    try? FileManager.default.removeItem(at: root)
  }
}

private final class SourceAnswers: @unchecked Sendable {
  struct State {
    var browse = Data()
    var collection = Data()
    var details: [String: [String: Any]] = [:]
    var profiles: [String: Data] = [:]
    var subscriptionPages: [Int: Data] = [:]
    var browseSections: [String] = []
    var detailsRequests = 0
    var cookies: [String?] = []
  }
  private let lock = NSLock()
  private var state = State()
  func read<T>(_ body: (State) -> T) -> T { lock.withLock { body(state) } }
  func write(_ body: (inout State) -> Void) { lock.withLock { body(&state) } }

  /// The status and body Steam would answer `request` with.
  func answer(_ request: URLRequest, body: Data) -> (Int, Data) {
    guard let url = request.url, let host = url.host else { return (404, Data()) }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let value = { (name: String) in query.first { $0.name == name }?.value }
    // `URL.path` drops a trailing slash.
    let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
    return lock.withLock {
      if host == "steamcommunity.com" { state.cookies.append(request.value(forHTTPHeaderField: "Cookie")) }
      switch (host, path) {
      case ("steamcommunity.com", "/workshop/browse"):
        state.browseSections.append(value("section") ?? "")
        return (200, state.browse)
      case ("api.steampowered.com", "/ISteamRemoteStorage/GetCollectionDetails/v1"):
        return (200, state.collection)
      case ("api.steampowered.com", "/ISteamRemoteStorage/GetPublishedFileDetails/v1"):
        state.detailsRequests += 1
        let form = String(decoding: body, as: UTF8.self)
        let ids = form.split(separator: "&").filter { $0.hasPrefix("publishedfileids") }
          .compactMap { $0.split(separator: "=").last.map(String.init) }
        let rows: [[String: Any]] = ids.map { state.details[$0] ?? ["publishedfileid": $0, "result": 9] }
        let json = try? JSONSerialization.data(withJSONObject: ["response": ["publishedfiledetails": rows]])
        return (200, json ?? Data())
      default:
        let parts = path.split(separator: "/")
        guard host == "steamcommunity.com", parts.count == 3, parts[0] == "profiles", parts[2] == "myworkshopfiles"
        else { return (404, Data()) }
        if value("browsefilter") == "mysubscriptions" {
          return (200, state.subscriptionPages[Int(value("p") ?? "1") ?? 1] ?? Data())
        }
        return (200, state.profiles[String(parts[1])] ?? Data())
      }
    }
  }
}

private final class SourceFixtureProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var registry: [String: SourceAnswers] = [:]

  static func register(_ identifier: String, answers: SourceAnswers) {
    lock.withLock { registry[identifier] = answers }
  }
  static func remove(_ identifier: String) {
    _ = lock.withLock { registry.removeValue(forKey: identifier) }
  }
  // Installed only in fixture sessions: every request is claimed, so none reaches the network.
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let answers = Self.lock.withLock { Self.registry[request.value(forHTTPHeaderField: "X-Source-Test") ?? ""] }
    guard let answers, let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
      return
    }
    let (status, data) = answers.answer(request, body: Self.body(of: request))
    let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}

  /// A POST body reaches a protocol as a stream.
  private static func body(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      guard read > 0 else { break }
      data.append(buffer, count: read)
    }
    return data
  }
}
