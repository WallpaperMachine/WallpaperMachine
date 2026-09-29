import Foundation
import Observation

struct WorkshopQuery: Equatable, Sendable {
  let text: String
  let kind: WorkshopKind
  let sort: WorkshopSort
  /// Steam `requiredtags[]`: every one must be on an item.
  var tags: [String] = []
  /// Steam `excludedtags[]`: an item carrying any of them is dropped.
  var excludedTags: [String] = []
  /// Where the tiles come from; only the browse and collections lists read `text` and `sort`.
  var source: WorkshopSource = .browse
}

struct WorkshopRequest: Equatable, Sendable {
  let query: WorkshopQuery
  let page: Int
}

/// Prerequisites are resolved in this order; a request reports the first one it still needs.
enum WorkshopDownloadStage: String, Sendable {
  case setup, account, resources, ready
}

/// A retained download intent. One click keeps the wallpaper the user asked for while
/// the runtime, the Steam account, and shared scene assets are resolved in turn.
struct WorkshopDownloadRequest: Identifiable, Sendable {
  /// Workshop item id, `WorkshopStore.sceneAssetsRequestID` for the shared assets download, or
  /// `WorkshopStore.signInRequestID` for a sign-in that downloads nothing.
  let id: String
  let item: WorkshopItem?
  var account: String
  var rememberSession: Bool
  /// Explicit consent to download Wallpaper Engine's multi-gigabyte shared assets.
  var includesResources: Bool
  /// The downloader rejected these inputs; only a fresh continuation may retry them, so
  /// automatic resumption cannot spin on the same rejected account.
  var refused = false
}

@MainActor
@Observable
final class WorkshopStore {
  var searchText = ""
  var kind: WorkshopKind = .all
  var sort: WorkshopSort = .trendingYear
  var tags: [String] = []
  var excludedTags: [String] = WorkshopStore.defaultExcludedTags
  /// Wallpaper Engine's own defaults: the sidebar lists every Type, Age rating, Resolution and
  /// Genre tag as a checkbox and unchecking one excludes it. Out of the box only Everyone is
  /// rated in, genre-less items are hidden, and Application / Asset are never offered.
  static let defaultExcludedTags = ["Application", "Asset", "Questionable", "Mature", "Unspecified"]
  var selectedItem: WorkshopItem?
  /// Where the next search looks. Opening an author or a collection remembers the source it
  /// was opened from, so Back returns to it.
  var source: WorkshopSource = .browse
  private(set) var sourceHistory: [WorkshopSource] = []
  /// The shown source's own name when it has one Steam gave, such as an author's.
  private(set) var sourceTitle: String?
  /// The Steam Community session subscriptions are read with. Memory only: it ends with the
  /// app, or on Sign Out.
  private(set) var steamWebSession: SteamWebSession?
  private(set) var isSigningInToSteamWeb = false
  private(set) var sceneAssetsReady: Bool
  @ObservationIgnored private let sceneAssetsAvailable: @MainActor () -> Bool

  func refreshSceneAssetsReadiness() {
    sceneAssetsReady = sceneAssetsAvailable()
  }
  private(set) var items: [WorkshopItem] = []
  private(set) var page = 1
  private(set) var totalPages = 1
  private(set) var totalCount = 0
  /// Results Steam can actually serve for the committed query: its result count capped by
  /// its 1,000 pages of 30, so the last page never asks for an unreachable item.
  private(set) var reachableCount = 0
  /// A panel page is exactly one Steam page: 30 tiles, and never more than 1,000 pages. The
  /// grid lays those tiles out in as many columns as its width holds and scrolls the rest,
  /// so a window resize only reflows the tiles and never changes what a page holds.
  static let pageSize = WorkshopService.pageSize
  static let maxPages = WorkshopService.maxPages
  private(set) var isLoading = false
  private(set) var hasLoaded = false
  var errorMessage: String?
  let downloader: WorkshopDownloadManager
  let steamCMDSetup: SteamCMDSetupStore
  /// Which installed Workshop wallpapers have updates; an update downloads like any item.
  let updates: WorkshopUpdateStore
  @ObservationIgnored private let service: WorkshopService
  @ObservationIgnored private let defaults: UserDefaults
  static let concurrentDownloadsKey = "WallpaperMachine.concurrentDownloads"
  var username = ""
  var selectedDownloadID: String?
  var showsDownloadDetails = false
  private(set) var downloadRequests: [WorkshopDownloadRequest] = []

  static let sceneAssetsRequestID = "scene-assets"
  static let signInRequestID = WorkshopDownloadManager.signInID

  var hasDownloadActivity: Bool { !downloader.downloads.isEmpty || !downloadRequests.isEmpty }
  var selectedDownload: WorkshopDownload? {
    downloader.downloads.first { $0.id == selectedDownloadID }
      ?? downloader.downloads.first { $0.isPending }
      ?? downloader.downloads.last
  }

  /// A finished wallpaper download stays valid even when the shared assets job fails, so the
  /// missing scene readiness needs its own standing warning instead of a transient job error.
  var sceneAssetsFailure: String? {
    guard !sceneAssetsReady, let job = downloader.download(for: nil), !job.isPending else {
      return nil
    }
    if job.isCancelled {
      return String(
        localized: "Shared scene assets were not installed, so scene wallpapers cannot play yet.")
    }
    return job.worker.errorMessage.map {
      String(
        localized:
          "Shared scene assets are still missing, so scene wallpapers cannot play yet: \($0)")
    }
  }

  convenience init(service: WorkshopService = WorkshopService()) {
    self.init(service: service, downloader: WorkshopDownloadManager())
  }

  init(
    service: WorkshopService = WorkshopService(), downloader: WorkshopDownloadManager,
    supportDirectory: URL = ClientPaths.supportURL, defaults: UserDefaults = .standard,
    runtimeProvider: any SteamCMDRuntimeProviding = SteamCMDRuntimeService(),
    updates: WorkshopUpdateStore? = nil,
    sceneAssetsAvailable: @escaping @MainActor () -> Bool = {
      ClientPaths.hasSceneAssets(at: ClientPaths.assetsURL)
    }
  ) {
    self.service = service
    self.downloader = downloader
    self.updates = updates ?? WorkshopUpdateStore(defaults: defaults)
    self.defaults = defaults
    self.sceneAssetsAvailable = sceneAssetsAvailable
    sceneAssetsReady = sceneAssetsAvailable()
    if let saved = defaults.object(forKey: Self.concurrentDownloadsKey) as? Int {
      downloader.setMaximumConcurrentDownloads(saved)
    }
    self.steamCMDSetup = SteamCMDSetupStore(
      downloader: downloader, supportDirectory: supportDirectory,
      defaults: defaults, runtimeProvider: runtimeProvider)
  }

  func showDownload(_ job: WorkshopDownload) {
    guard downloader.downloads.contains(where: { $0 === job }) else { return }
    selectedDownloadID = job.id
    showsDownloadDetails = true
  }

  /// How many Workshop downloads may run at once; kept across launches.
  func setConcurrentDownloads(_ count: Int) {
    downloader.setMaximumConcurrentDownloads(count)
    defaults.set(downloader.maximumConcurrentDownloads, forKey: Self.concurrentDownloadsKey)
  }

  /// The entry point for a single click: start immediately when every prerequisite is met,
  /// otherwise retain the intent and report which prerequisite it is waiting on.
  func requestDownload(item: WorkshopItem?, rememberSession: Bool, bridge: BridgeStore) {
    let id = item?.id ?? Self.sceneAssetsRequestID
    if let job = downloader.download(for: item?.id), job.isPending {
      showDownload(job)
      return
    }
    let existing = downloadRequests.first { $0.id == id }
    let retained = existing?.account ?? ""
    resolve(
      WorkshopDownloadRequest(
        id: id, item: item ?? existing?.item,
        account: retained.isEmpty ? suggestedAccount : retained,
        // A retained request keeps the choice it was continued with.
        rememberSession: existing?.rememberSession ?? rememberSession,
        includesResources: existing?.includesResources ?? false),
      bridge: bridge)
  }

  /// Signs in to Steam without downloading anything, so the account and its saved sign-in are in
  /// place before the first download. Rides the same ladder as a download: SteamCMD must be set
  /// up first, and a running sign-in is shown rather than started twice.
  func requestSignIn(account: String, rememberSession: Bool, bridge: BridgeStore) {
    if let job = downloader.signIn, job.isPending {
      showDownload(job)
      return
    }
    username = account
    resolve(
      WorkshopDownloadRequest(
        id: Self.signInRequestID, item: nil, account: account,
        rememberSession: rememberSession, includesResources: true),
      bridge: bridge)
  }

  /// Supplies the account and the consent a retained request is waiting on, then resumes it.
  /// Returns `false` when the id names neither a retained request nor a known Workshop item.
  @discardableResult
  func continueDownload(
    id: String, account: String, rememberSession: Bool,
    includeResources: Bool, bridge: BridgeStore
  ) -> Bool {
    let existing = downloadRequests.first { $0.id == id }
    let itemless = id == Self.sceneAssetsRequestID || id == Self.signInRequestID
    let item = itemless ? nil : existing?.item ?? workshopItem(id: id)
    guard itemless || item != nil else { return false }
    username = account
    resolve(
      WorkshopDownloadRequest(
        id: id, item: item, account: account,
        rememberSession: rememberSession,
        includesResources: existing?.includesResources == true || includeResources),
      bridge: bridge)
    return true
  }

  func removeDownloadRequest(id: String) {
    downloadRequests.removeAll { $0.id == id }
  }

  /// "Change account" stops exactly this job and keeps its wallpaper as an intent with no
  /// account, so nothing signs in again under the name the user rejected. Consent already
  /// given for shared assets is preserved; other queued jobs are untouched.
  func changeDownloadAccount(id: String) async {
    guard let job = downloader.downloads.first(where: { $0.id == id }) else { return }
    let item = job.item
    let rememberSession = downloader.rememberSessionWhileRunning ?? true
    downloader.cancel(job)
    await job.worker.shutdown()
    // The rejected name must not survive as the suggestion for this or any new intent.
    if Self.normalizedAccount(username) == Self.normalizedAccount(job.account) { username = "" }
    upsert(
      WorkshopDownloadRequest(
        id: id, item: item, account: "",
        rememberSession: rememberSession, includesResources: true,
        refused: true))
  }

  /// Driven by the control panel's observation loop: prerequisites change outside any user
  /// action, so a request that becomes startable continues without a second click.
  func resumeDownloadRequests(bridge: BridgeStore) {
    for request in downloadRequests {
      var request = request
      let suggestion = suggestedAccount
      // A rejected account must not be refilled from the saved or typed suggestion.
      if !request.refused, request.account.isEmpty, !suggestion.isEmpty {
        request.account = suggestion
        upsert(request)
      }
      if stage(for: request) == .ready { resolve(request, bridge: bridge) }
    }
  }

  func stage(for request: WorkshopDownloadRequest) -> WorkshopDownloadStage {
    if steamCMDSetup.isBusy || steamCMDSetup.selectedRuntime == nil { return .setup }
    if request.refused || Self.normalizedAccount(request.account).isEmpty { return .account }
    // A sign-in downloads nothing, so shared resources never come into it.
    if request.id == Self.signInRequestID { return .ready }
    if !request.includesResources, needsResources(request) { return .resources }
    return .ready
  }

  /// Resolves an item id against browsing results, the retained selection, retained requests,
  /// and running jobs, so an intent survives searching and paging away from the item.
  func workshopItem(id: String) -> WorkshopItem? {
    if let item = items.first(where: { $0.id == id }) { return item }
    if let selectedItem, selectedItem.id == id { return selectedItem }
    if let item = downloadRequests.first(where: { $0.id == id })?.item { return item }
    if let item = downloader.downloads.first(where: { $0.item?.id == id })?.item { return item }
    return updates.available[id]
  }

  /// A running session pins the account every queued job reuses; a name typed elsewhere must
  /// not seed an intent that would sign in as somebody else.
  var suggestedAccount: String {
    if let active = downloader.downloads.last(where: { $0.isPending })?.account { return active }
    let typed = username.trimmingCharacters(in: .whitespacesAndNewlines)
    return typed.isEmpty ? downloader.savedAccount ?? "" : typed
  }

  private var sharedAssetsPending: Bool { downloader.download(for: nil)?.isPending == true }

  /// Downloading Wallpaper Engine's shared assets is always an explicit choice, even when a
  /// copy is already installed. A scene only needs that consent while the assets are missing
  /// and no shared job is already running for it to ride.
  private func needsResources(_ request: WorkshopDownloadRequest) -> Bool {
    guard let item = request.item else { return true }
    return item.kind == .scene && !sceneAssetsReady && !sharedAssetsPending
  }

  private func needsSharedAssets(_ item: WorkshopItem) -> Bool {
    item.kind == .scene && !sceneAssetsReady
  }

  private func upsert(_ request: WorkshopDownloadRequest) {
    if let index = downloadRequests.firstIndex(where: { $0.id == request.id }) {
      downloadRequests[index] = request
    } else {
      downloadRequests.append(request)
    }
  }

  private func resolve(_ request: WorkshopDownloadRequest, bridge: BridgeStore) {
    guard stage(for: request) == .ready, let runtime = steamCMDSetup.selectedRuntime else {
      upsert(request)
      return
    }
    downloadRequests.removeAll { $0.id == request.id }
    if request.id == Self.signInRequestID {
      downloader.signIn(
        username: request.account, executable: runtime.executableURL,
        root: ClientPaths.libraryURL.deletingLastPathComponent(),
        rememberSession: request.rememberSession)
    } else if let item = request.item {
      // Shared assets are queued first and only once: other scenes ride the same job.
      if needsSharedAssets(item), !sharedAssetsPending {
        installAssets(request, runtime: runtime)
      }
      // A wallpaper already in the library is being updated: its new files replace the old,
      // and a display showing it loads them again.
      let replacing = bridge.librarySnapshot.wallpapers.contains { $0.id == item.id }
      downloader.start(
        item: item, username: request.account, executable: runtime.executableURL,
        library: ClientPaths.libraryURL, rememberSession: request.rememberSession
      ) { [updates] in
        // The files are already in the library, so the install counts even if the refresh fails.
        updates.recordInstalled(item.id)
        try await bridge.refreshLibraryAsync()
        guard replacing else { return }
        do {
          try await bridge.reloadWallpaperAsync(id: item.id)
        } catch {
          AppLog.warn("Workshop item \(item.id) was updated but could not be reloaded: \(error.localizedDescription)")
        }
      }
    } else {
      installAssets(request, runtime: runtime)
    }
    let started = request.id == Self.signInRequestID ? downloader.signIn : downloader.download(for: request.item?.id)
    if let job = started, job.isPending {
      selectedDownloadID = job.id
    } else if downloader.errorMessage != nil {
      // The downloader refused the inputs; keep the intent so the user can correct them.
      var refused = request
      refused.refused = true
      upsert(refused)
    }
  }

  private func installAssets(_ request: WorkshopDownloadRequest, runtime: SteamCMDRuntime) {
    let destination = ClientPaths.managedAssetsURL
    downloader.installAssets(
      username: request.account, executable: runtime.executableURL,
      destination: destination, rememberSession: request.rememberSession
    ) {
      try ClientPaths.configureAssetsFolder(at: destination)
      self.refreshSceneAssetsReadiness()
    }
  }

  func clearDownloadActivity() {
    downloader.clearCompleted()
    if !downloader.downloads.contains(where: { $0.id == selectedDownloadID }) {
      selectedDownloadID = nil
    }
    if !hasDownloadActivity { showsDownloadDetails = false }
  }

  static func normalizedAccount(_ account: String) -> String {
    account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()
  private(set) var committedQuery: WorkshopQuery?
  private(set) var failedRequest: WorkshopRequest?
  /// Steam pages fetched for `cacheQuery`, keyed by page number, plus fetches still in
  /// flight, so paging back never touches the network. A search always starts a fresh
  /// cache, even for the same query.
  @ObservationIgnored private var cacheQuery: WorkshopQuery?
  @ObservationIgnored private var cacheID = UUID()
  @ObservationIgnored private var steamPages: [Int: WorkshopPage] = [:]
  @ObservationIgnored private var steamFetches: [Int: Task<WorkshopPage, Error>] = [:]
  /// Fetches the page after the one on show in the background, so paging forward is served
  /// from the cache like paging back. Off unless the owner opts in.
  @ObservationIgnored var prefetchesNextPage = false
  /// Told the preview URLs of every Steam page as it arrives, shown or prefetched, so the
  /// owner of the preview cache can start on them before the panel asks.
  @ObservationIgnored var onPreviewsAvailable: (@MainActor ([URL]) -> Void)?

  private var draftQuery: WorkshopQuery {
    WorkshopQuery(
      text: searchText.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, sort: sort,
      tags: tags, excludedTags: excludedTags, source: source)
  }

  /// The Steam page showing the current page's tiles.
  var browseURL: URL {
    let query = committedQuery ?? draftQuery
    switch query.source {
    case .browse, .collections:
      return WorkshopService.browseURL(
        search: query.text, kind: query.source == .browse ? query.kind : .all, sort: query.sort,
        page: page, tags: query.tags, excludedTags: query.excludedTags,
        section: query.source == .browse ? "readytouseitems" : "collections")
    case .collection(let id, _):
      return URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(id)")!
    case .creator(let id, _):
      return WorkshopService.profileURL(steamID: id, subscriptions: false, page: page)
    case .subscriptions:
      return steamWebSession.map { WorkshopService.profileURL(steamID: $0.steamID, subscriptions: true, page: page) }
        ?? URL(string: "https://steamcommunity.com/app/\(WorkshopApp.id)/workshop/")!
    }
  }

  func search() {
    resetCache(for: draftQuery)
    load(WorkshopRequest(query: draftQuery, page: 1))
  }

  /// Shows another source from its first page. An author or a collection is opened from what
  /// is on show, so Back can return there; choosing a list afresh starts a new history.
  func open(_ next: WorkshopSource) {
    switch next {
    case .creator, .collection:
      let current = committedQuery?.source ?? source
      if current != next { sourceHistory.append(current) }
    case .browse, .collections, .subscriptions:
      sourceHistory = []
    }
    source = next
    selectedItem = nil
    search()
  }

  /// Returns to the source the shown one was opened from, from its first page.
  func back() {
    guard let previous = sourceHistory.popLast() else { return }
    source = previous
    selectedItem = nil
    search()
  }

  /// Signs in to Steam Community through Steam's own page, so subscriptions can be read. The
  /// app never sees the password: `obtainCookie` answers the session cookie Steam set, or nil
  /// when the window was closed first.
  func signInToSteamWeb(obtainCookie: @MainActor () async -> String?) async throws {
    guard !isSigningInToSteamWeb else { return }
    isSigningInToSteamWeb = true
    defer { isSigningInToSteamWeb = false }
    guard let cookie = await obtainCookie() else { return }
    guard let session = SteamWebSession(cookie: cookie) else {
      throw WorkshopFailure(message: String(localized: "Steam’s sign-in finished without a session this app can use. Try signing in again."))
    }
    steamWebSession = session
    if (committedQuery?.source ?? source) == .subscriptions { search() }
  }

  /// Forgets the Steam Community session; Steam's own sign-in window keeps no cookie either.
  func signOutOfSteamWeb() {
    steamWebSession = nil
    if (committedQuery?.source ?? source) == .subscriptions {
      cancelSearch()
      items = []
      totalCount = 0
      totalPages = 1
      reachableCount = 0
      committedQuery = nil
      hasLoaded = false
    }
  }

  /// The ids of subscribed wallpapers not in `installed`, asking Steam for every page of
  /// subscriptions. Throws `SteamSignInRequired` when the session has ended.
  func missingSubscriptions(installed: Set<String>) async throws -> [WorkshopItem] {
    guard let session = steamWebSession else { throw SteamSignInRequired() }
    do {
      let ids = try await service.subscribedIDs(account: session).filter { !installed.contains($0) }
      return try await service.details(ids: ids).filter { $0.collectionSize == nil }
    } catch is SteamSignInRequired {
      steamWebSession = nil
      throw SteamSignInRequired()
    }
  }

  func loadPage(_ page: Int) {
    guard let committedQuery, page >= 1, page <= totalPages else { return }
    load(WorkshopRequest(query: committedQuery, page: page))
  }

  func retrySearch() {
    guard let failedRequest else { return }
    load(failedRequest)
  }

  /// Drops every in-flight fetch. Cached pages survive unless the query changed or the caller
  /// asked for fresh results; the new cache id keeps late completions of old fetches out.
  private func resetCache(for query: WorkshopQuery?) {
    for task in steamFetches.values { task.cancel() }
    steamFetches = [:]
    cacheID = UUID()
    if let query {
      steamPages = [:]
      cacheQuery = query
    }
  }

  /// Starts, or joins, the fetch of one Steam page for the current cache.
  private func fetchSteamPage(_ number: Int, query: WorkshopQuery) -> Task<WorkshopPage, Error> {
    if let task = steamFetches[number] { return task }
    let cacheID = cacheID
    let service = service
    let task = Task { [weak self] in
      defer { if let self, self.cacheID == cacheID { self.steamFetches[number] = nil } }
      let result = try await service.page(for: query, page: number, account: self?.steamWebSession)
      try Task.checkCancellation()
      // Only the cache that asked keeps the page; a superseded fetch is simply dropped.
      if let self, self.cacheID == cacheID {
        self.steamPages[number] = result
        self.onPreviewsAvailable?(result.items.compactMap(\.previewURL))
      }
      return result
    }
    steamFetches[number] = task
    return task
  }

  /// Steam's own `total_pages` is already clamped to 1,000; clamping again keeps the panel's
  /// page count within that limit whatever a page says, so no page beyond it is ever offered.
  private func publish(_ result: WorkshopPage, for request: WorkshopRequest) {
    var seen = Set<String>()
    items = result.items.filter { seen.insert($0.id).inserted }
    totalCount = result.totalCount
    totalPages = min(Self.maxPages, max(1, result.totalPages))
    reachableCount = min(result.totalCount, totalPages * Self.pageSize)
    page = min(totalPages, request.page)
    hasLoaded = true
    committedQuery = request.query
    sourceTitle = result.title
    failedRequest = nil
    // A failed prefetch is simply retried as an ordinary load when the user gets there.
    if prefetchesNextPage, page < totalPages, steamPages[page + 1] == nil {
      _ = fetchSteamPage(page + 1, query: request.query)
    }
  }

  private func load(_ request: WorkshopRequest) {
    searchTask?.cancel()
    if cacheQuery != request.query { resetCache(for: request.query) }
    generation = UUID()
    errorMessage = nil
    // A page already in the cache (paging back) never shows as loading.
    if let cached = steamPages[request.page] {
      isLoading = false
      publish(cached, for: request)
      return
    }
    let requestID = generation
    isLoading = true
    searchTask = Task {
      do {
        let result = try await fetchSteamPage(request.page, query: request.query).value
        guard generation == requestID, !Task.isCancelled else { return }
        publish(result, for: request)
      } catch {
        guard generation == requestID, !Task.isCancelled else { return }
        // Steam ended the session: forget it, so the panel offers to sign in again.
        if error is SteamSignInRequired { steamWebSession = nil }
        errorMessage = error.localizedDescription
        failedRequest = request
      }
      if generation == requestID {
        isLoading = false
      }
    }
  }

  func cancelSearch() {
    searchTask?.cancel()
    resetCache(for: nil)
    generation = UUID()
    isLoading = false
  }

}
