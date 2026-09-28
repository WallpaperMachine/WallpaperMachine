import Foundation
import Observation

/// The pixiv tab's state: the query, one page of results, the selected work with its pages,
/// the downloads under way, and the pixiv account the user signed in to, if any.
///
/// pixiv answers a listing (a ranking, or a search with its server-side filters); the age
/// rating and, for rankings, orientation and size are applied here to the works it returned.
/// Pages are cached per listing, so paging back, and changing a filter pixiv never sees, cost
/// no request at all.
///
/// Signing in happens on pixiv's own page, which hands over the session it sets; the session
/// is checked with pixiv, kept in the keychain and sent with every request to pixiv's site.
/// R-18 works are asked for only while a session is held and the Mature box is ticked.
@MainActor
@Observable
final class PixivStore {
    /// The query the page edits; `apply(_:refresh:)` commits it.
    private(set) var query = PixivQuery()
    /// The query the results on show answer.
    private(set) var committedQuery: PixivQuery?
    /// The works on the page on show that the committed query admits, in pixiv's order.
    private(set) var works: [PixivWork] = []
    /// Works pixiv returned for this page that the committed query's filters hide.
    private(set) var hiddenCount = 0
    private(set) var page = 1
    private(set) var totalPages = 1
    private(set) var totalCount = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var selectedWork: PixivWork?
    /// Page of the selected work the inspector shows and would download.
    private(set) var selectedPage = 0
    /// The selected work's pages: nil while they load, or the reason they could not.
    private(set) var selectedPages: Result<[PixivPage], PixivFailure>?
    let downloads: PixivDownloadQueue
    /// The account the held session signs in to, once pixiv confirmed it.
    private(set) var account: PixivAccount?
    /// The sign-in page is open, or the session it produced is being checked.
    private(set) var isSigningIn = false
    /// Why the last sign-in did not take, or that pixiv ended the session.
    private(set) var accountMessage: String?
    /// The signed-in `PHPSESSID`. Never logged, and sent to `www.pixiv.net` only.
    private var session: String?
    /// Fetches the page after the one on show in the background; off unless the owner opts in.
    @ObservationIgnored var prefetchesNextPage = false
    /// Told every thumbnail address as a page arrives, so the owner can start caching them.
    @ObservationIgnored var onThumbnailsAvailable: (@MainActor ([URL]) -> Void)?
    @ObservationIgnored private let service: PixivService
    @ObservationIgnored private let sessions: any PixivSessionStoring
    @ObservationIgnored private var signInTask: Task<Void, Never>?
    @ObservationIgnored private var accountTask: Task<Void, Never>?
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var cacheListing: PixivListing?
    @ObservationIgnored private var cacheID = UUID()
    @ObservationIgnored private var cachedPages: [Int: PixivResultPage] = [:]
    @ObservationIgnored private var fetches: [Int: Task<PixivResultPage, Error>] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var failedPage: Int?
    @ObservationIgnored private var pageLists: [String: [PixivPage]] = [:]
    @ObservationIgnored private var pageListOrder: [String] = []
    @ObservationIgnored private var pagesTask: Task<Void, Never>?
    private static let pageListLimit = 64

    /// `sessions` is read only by `restoreSession()`, and written only when signing in or out
    /// or when pixiv has ended the session.
    init(
        service: PixivService = PixivService(), packager: PixivWallpaperPackager = PixivWallpaperPackager(),
        sessions: any PixivSessionStoring = KeychainPixivSessionStore()
    ) {
        self.service = service
        self.sessions = sessions
        downloads = PixivDownloadQueue(service: service, packager: packager)
    }

    var isSignedIn: Bool { session != nil }

    /// Commits `query`, as far as the account allows (see `PixivQuery.sanitized(signedIn:)`).
    /// A different listing, or `refresh`, fetches its first page afresh; otherwise only the
    /// app-side filters changed and the page on show is filtered again, or, while it is still
    /// loading, published with them when it arrives.
    func apply(_ query: PixivQuery, refresh: Bool = false) {
        let query = query.sanitized(signedIn: isSignedIn)
        self.query = query
        if !refresh, cacheListing == query.listing {
            if isLoading { return }
            if committedQuery?.listing == query.listing, let cached = cachedPages[page] {
                publish(cached, for: query)
                return
            }
        }
        resetCache(for: query.listing)
        load(page: 1, of: query)
    }

    func loadPage(_ number: Int) {
        guard let committedQuery, number >= 1, number <= totalPages else { return }
        load(page: number, of: committedQuery)
    }

    func retry() {
        load(page: failedPage ?? page, of: committedQuery ?? query)
    }

    /// Resolves a work id against the page on show, the selection and the downloads, so a
    /// work stays reachable after paging away from it.
    func work(id: String) -> PixivWork? {
        works.first { $0.id == id } ?? (selectedWork?.id == id ? selectedWork : nil)
            ?? downloads.downloads.first { $0.work.id == id }?.work
    }

    func select(_ work: PixivWork) {
        guard selectedWork?.id != work.id else { return }
        selectedWork = work
        selectedPage = 0
        loadPages(of: work)
    }

    func selectPage(_ index: Int) {
        guard let selectedWork, index >= 0, index < pageCount(of: selectedWork) else { return }
        selectedPage = index
    }

    /// The selected work's pages once known; nil while they load or when they could not.
    var selectedPageList: [PixivPage]? {
        if case .success(let pages) = selectedPages { pages } else { nil }
    }

    /// The page list, once fetched, is authoritative; a listing may predate pages added since.
    func pageCount(of work: PixivWork) -> Int {
        pageLists[work.id]?.count ?? work.pageCount
    }

    // MARK: - Account

    /// Takes up the session an earlier launch saved, if any, and confirms it with pixiv in the
    /// background. The keychain is read off the main actor, since it may ask the user first.
    func restoreSession() {
        guard restoreTask == nil, session == nil else { return }
        let sessions = sessions
        restoreTask = Task { [weak self] in
            let saved = await Task.detached(priority: .userInitiated) { sessions.load() }.value
            guard let self, !Task.isCancelled, self.session == nil, self.signInTask == nil,
                let saved, PixivService.isSessionValue(saved)
            else { return }
            self.use(saved, account: nil)
            self.checkAccount()
        }
    }

    /// Opens pixiv's sign-in through `obtainSession`, which answers the session pixiv set, or
    /// nil when the user gave up; a session pixiv confirms replaces the one held, if any.
    func signIn(obtainingSessionWith obtainSession: @escaping @MainActor () async -> String?) {
        guard signInTask == nil else { return }
        isSigningIn = true
        accountMessage = nil
        signInTask = Task { [weak self] in
            let candidate = await obtainSession()
            // Signing out cancels the sign-in and resets its state itself.
            guard let self, !Task.isCancelled else { return }
            if let candidate { await self.adopt(candidate) }
            guard !Task.isCancelled else { return }
            self.isSigningIn = false
            self.signInTask = nil
        }
    }

    /// Forgets the session, here and in the keychain, and shows what an anonymous visitor
    /// sees. pixiv itself keeps the session until it expires or is signed out on pixiv.
    func signOut() {
        restoreTask?.cancel()
        signInTask?.cancel()
        signInTask = nil
        isSigningIn = false
        sessions.remove()
        accountMessage = nil
        use(nil, account: nil)
    }

    private func adopt(_ candidate: String) async {
        guard PixivService.isSessionValue(candidate) else {
            accountMessage = PixivFailure(code: .signedOut).localizedDescription
            return
        }
        do {
            guard let account = try await service.account(session: candidate) else {
                accountMessage = PixivFailure(code: .signedOut).localizedDescription
                return
            }
            guard !Task.isCancelled else { return }
            do {
                try sessions.save(candidate)
            } catch {
                accountMessage = error.localizedDescription
            }
            AppLog.info("pixiv signed in")
            use(candidate, account: account)
        } catch is CancellationError {
            return
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    /// Confirms the held session with pixiv. A definite "no one is signed in" drops it; a
    /// failure to ask keeps it, and the account stays unconfirmed.
    private func checkAccount() {
        guard let session, accountTask == nil else { return }
        let service = service
        accountTask = Task { [weak self] in
            let account: PixivAccount?
            do {
                account = try await service.account(session: session)
            } catch {
                // A cancelled check was already replaced; any other failure leaves the session.
                if !Task.isCancelled { self?.accountTask = nil }
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.accountTask = nil
            guard self.session == session else { return }
            if let account {
                self.account = account
            } else {
                AppLog.info("pixiv ended the saved sign-in")
                self.sessions.remove()
                self.use(nil, account: nil)
                self.accountMessage = PixivFailure(code: .signedOut).localizedDescription
            }
        }
    }

    /// Switches every later request to `session`. What was fetched with the old one is
    /// dropped: the listing reloads, and so do the selected work's pages.
    private func use(_ session: String?, account: PixivAccount?) {
        accountTask?.cancel()
        accountTask = nil
        self.session = session
        self.account = account
        downloads.session = session
        pageLists = [:]
        pageListOrder = []
        if session == nil, selectedWork?.rating == .mature {
            pagesTask?.cancel()
            selectedWork = nil
            selectedPages = nil
            selectedPage = 0
        } else if let selectedWork {
            loadPages(of: selectedWork)
        }
        let query = query.sanitized(signedIn: session != nil)
        if hasLoaded || isLoading || committedQuery != nil {
            apply(query, refresh: true)
        } else {
            self.query = query
        }
    }

    func requestDownload(_ work: PixivWork, page: Int) {
        guard page >= 0, page < pageCount(of: work) else { return }
        downloads.enqueue(work, page: page, knownPages: pageLists[work.id])
    }

    func retrySelectedPages() {
        guard let selectedWork else { return }
        loadPages(of: selectedWork)
    }

    private func loadPages(of work: PixivWork) {
        pagesTask?.cancel()
        if let known = pageLists[work.id] {
            selectedPages = .success(known)
            return
        }
        selectedPages = nil
        let service = service
        let session = session
        pagesTask = Task { [weak self] in
            let result: Result<[PixivPage], PixivFailure>
            do {
                result = .success(try await service.pages(ofWork: work.id, session: session))
            } catch is CancellationError {
                return
            } catch {
                result = .failure(error as? PixivFailure ?? PixivFailure(code: .network(error.localizedDescription)))
            }
            guard let self, !Task.isCancelled, self.selectedWork?.id == work.id else { return }
            if case .success(let pages) = result {
                self.remember(pages, for: work.id)
                self.onThumbnailsAvailable?(pages.compactMap(\.previewURL))
            }
            self.selectedPages = result
        }
    }

    private func remember(_ pages: [PixivPage], for id: String) {
        if pageLists.updateValue(pages, forKey: id) == nil { pageListOrder.append(id) }
        while pageListOrder.count > Self.pageListLimit {
            pageLists[pageListOrder.removeFirst()] = nil
        }
    }

    /// Drops every in-flight fetch and, for a new listing, every cached page; the new cache id
    /// keeps late completions of old fetches out.
    private func resetCache(for listing: PixivListing) {
        for task in fetches.values { task.cancel() }
        fetches = [:]
        cachedPages = [:]
        cacheListing = listing
        cacheID = UUID()
    }

    /// Starts, or joins, the fetch of one page for the current cache.
    private func fetch(_ number: Int, of listing: PixivListing) -> Task<PixivResultPage, Error> {
        if let task = fetches[number] { return task }
        let cacheID = cacheID
        let service = service
        let session = session
        let task = Task { [weak self] in
            defer { if let self, self.cacheID == cacheID { self.fetches[number] = nil } }
            let result = try await service.page(number, of: listing, session: session)
            try Task.checkCancellation()
            if let self, self.cacheID == cacheID {
                self.cachedPages[number] = result
                self.onThumbnailsAvailable?(result.works.compactMap(\.thumbnailURL))
            }
            return result
        }
        fetches[number] = task
        return task
    }

    private func load(page number: Int, of query: PixivQuery) {
        loadTask?.cancel()
        if cacheListing != query.listing { resetCache(for: query.listing) }
        generation = UUID()
        errorMessage = nil
        if let cached = cachedPages[number] {
            isLoading = false
            publish(cached, for: query)
            return
        }
        let requestID = generation
        let listing = query.listing
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.fetch(number, of: listing).value
                guard self.generation == requestID, !Task.isCancelled else { return }
                // Filters changed while the page loaded apply to it as it arrives.
                self.publish(result, for: self.query.listing == listing ? self.query : query)
            } catch {
                guard self.generation == requestID, !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.failedPage = number
                self.committedQuery = query
                // pixiv refusing an R-18 ranking may mean it ended the session.
                if let failure = error as? PixivFailure, failure.code == .r18Hidden { self.checkAccount() }
            }
            if self.generation == requestID { self.isLoading = false }
        }
    }

    private func publish(_ result: PixivResultPage, for query: PixivQuery) {
        works = result.works.filter(query.admits)
        hiddenCount = result.works.count - works.count
        totalPages = min(PixivService.maxPages, max(1, result.totalPages, result.page))
        totalCount = result.totalCount
        page = min(totalPages, max(1, result.page))
        hasLoaded = true
        committedQuery = query
        errorMessage = nil
        failedPage = nil
        // A failed prefetch is simply retried as an ordinary load when the user gets there.
        if prefetchesNextPage, page < totalPages, cachedPages[page + 1] == nil {
            _ = fetch(page + 1, of: query.listing)
        }
    }
}
