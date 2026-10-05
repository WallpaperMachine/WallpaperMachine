import Foundation
import XCTest

@testable import WallpaperMachine

@MainActor
final class PixivStoreTests: XCTestCase {
    private typealias Work = PixivFixtures.Work

    private func store(
        _ transport: PixivFixtureTransport, sessions: PixivMemorySessionStore = PixivMemorySessionStore()
    ) -> PixivStore {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent("pixiv-store-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: library) }
        let service = PixivService(transport: transport, minimumInterval: .zero)
        return PixivStore(
            service: service, packager: PixivWallpaperPackager(library: library) { data, _ in data }, sessions: sessions)
    }

    /// pixiv as a signed-in member sees it: the status names the account for `PixivFixtures.session`
    /// only, until `ended` is set, and R-18 rankings answer that session alone.
    private nonisolated static func member(ended: LockedFlag = LockedFlag()) -> PixivFixtureTransport {
        PixivFixtureTransport(respondingToSession: { url, session in
            let known = session == PixivFixtures.session && !ended.value
            switch url.path {
            case "/touch/ajax/user/self/status":
                return PixivFixtures.status(signedIn: known)
            case "/ranking.php":
                let mode = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first { $0.name == "mode" }?.value ?? ""
                if mode.hasSuffix("_r18"), !known { throw PixivFixtures.forbidden }
                return ranking(url)
            default:
                return PixivFixtures.pages(workID: Int(url.pathComponents.dropLast().last ?? "") ?? 0, count: 1)
            }
        })
    }

    private func mode(of url: URL?) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "mode" }?.value }
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A daily ranking of `total` works whose page `p` holds three: one wide, one tall, one suggestive.
    private nonisolated static func ranking(_ url: URL, total: Int = 150) -> Data {
        let page = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "p" }?.value ?? "1") ?? 1
        let base = page * 10
        return PixivFixtures.ranking([
            PixivFixtures.rankingEntry(Work(id: base + 1, width: 2560, height: 1440), rank: 1),
            PixivFixtures.rankingEntry(Work(id: base + 2, width: 1000, height: 1600), rank: 2),
            PixivFixtures.rankingEntry(Work(id: base + 3, sexual: 1), rank: 3),
        ], page: page, total: total)
    }

    func testRankingOpensFilteredToAllAgesWorks() async throws {
        let transport = PixivFixtureTransport { Self.ranking($0) }
        let store = store(transport)

        store.apply(PixivQuery())
        XCTAssertTrue(store.isLoading)
        try await waitUntil { store.hasLoaded }

        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.works.map(\.id), ["11", "12"])
        XCTAssertEqual(store.hiddenCount, 1)
        XCTAssertEqual(store.page, 1)
        XCTAssertEqual(store.totalPages, 3)
        XCTAssertEqual(store.totalCount, 150)
        XCTAssertEqual(store.committedQuery, PixivQuery())
    }

    func testFiltersPixivNeverSeesReuseThePageOnShow() async throws {
        let transport = PixivFixtureTransport { Self.ranking($0) }
        let store = store(transport)
        store.apply(PixivQuery())
        try await waitUntil { store.hasLoaded }

        var query = PixivQuery()
        query.ratings = [.everyone, .questionable]
        store.apply(query)
        XCTAssertEqual(store.works.map(\.id), ["11", "12", "13"])
        query.orientation = .landscape
        store.apply(query)
        XCTAssertEqual(store.works.map(\.id), ["11", "13"])
        XCTAssertEqual(store.hiddenCount, 1)
        XCTAssertEqual(transport.requests.count, 1, "app-side filters never ask pixiv again")

        query.ranking = .weekly
        store.apply(query)
        try await waitUntil { store.committedQuery?.ranking == .weekly }
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(transport.requests.last), resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "mode" }?.value, "weekly")
    }

    /// A search that fails to open does not leave the ranking's works on show under it, where
    /// Next would page the failed search; Retry still asks for that search.
    func testAFailedNewListingClearsTheWorksOfTheOneBefore() async throws {
        let transport = PixivFixtureTransport { url in
            if url.path.hasPrefix("/ajax/search/") { throw PixivFailure(code: .status(429)) }
            return Self.ranking(url)
        }
        let store = store(transport)
        store.apply(PixivQuery())
        try await waitUntil { store.hasLoaded }
        XCTAssertFalse(store.works.isEmpty)

        store.apply(PixivQuery(text: "sky"))
        try await waitUntil { store.errorMessage != nil }
        XCTAssertFalse(store.hasLoaded)
        XCTAssertTrue(store.works.isEmpty)
        XCTAssertEqual(store.totalCount, 0)
        XCTAssertEqual(store.totalPages, 1)
        store.retry()
        try await waitUntil { !store.isLoading }
        XCTAssertEqual(transport.requests.last?.path, "/ajax/search/illustrations/sky")
    }

    func testRefreshAsksPixivAgainForTheSameListing() async throws {
        let transport = PixivFixtureTransport { Self.ranking($0) }
        let store = store(transport)
        store.apply(PixivQuery())
        try await waitUntil { store.hasLoaded }

        store.apply(PixivQuery(), refresh: true)
        try await waitUntil { !store.isLoading }

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testPagingBackIsServedFromTheCacheAndTheNextPageIsPrefetched() async throws {
        let transport = PixivFixtureTransport { Self.ranking($0) }
        let store = store(transport)
        store.prefetchesNextPage = true
        store.apply(PixivQuery())
        try await waitUntil { store.hasLoaded && transport.requests.count == 2 }

        store.loadPage(2)
        try await waitUntil { store.page == 2 && !store.isLoading }
        XCTAssertEqual(store.works.first?.id, "21")
        try await waitUntil { transport.requests.count == 3 }
        store.loadPage(1)
        XCTAssertFalse(store.isLoading, "a page seen before shows at once")
        XCTAssertEqual(store.works.first?.id, "11")
        store.loadPage(4)
        XCTAssertEqual(store.page, 1, "pages past the ranking's end are not offered")

        let pages = transport.requests.compactMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "p" }?.value
        }
        XCTAssertEqual(pages, ["1", "2", "3"], "each page is asked for once, the next one ahead of time")
    }

    func testSearchReportsPixivsPageCountAndRetriesAfterAFailure() async throws {
        let failing = LockedFlag()
        failing.value = true
        let transport = PixivFixtureTransport { _ in
            if failing.value { throw PixivFailure(code: .status(429)) }
            return PixivFixtures.search(
                [PixivFixtures.searchEntry(Work(id: 5, aiType: 2)), PixivFixtures.searchEntry(Work(id: 6))],
                total: 600, lastPage: 10)
        }
        let store = store(transport)
        var query = PixivQuery(text: "sky")
        query.hidesAIGenerated = true

        store.apply(query)
        try await waitUntil { store.errorMessage != nil }
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.errorMessage, PixivFailure(code: .status(429)).localizedDescription)
        XCTAssertFalse(store.hasLoaded)

        failing.value = false
        store.retry()
        try await waitUntil { store.hasLoaded }
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.works.map(\.id), ["6"], "AI-generated works stay hidden when asked")
        XCTAssertEqual(store.totalPages, 10)
        XCTAssertEqual(store.totalCount, 600)
        XCTAssertEqual(transport.requests.last?.path, "/ajax/search/illustrations/sky")
    }

    func testSelectingAWorkLoadsItsPagesOnceAndPicksAPage() async throws {
        // The listing still says one page; the page list pixiv sends when asked is what counts.
        let transport = PixivFixtureTransport { url in
            url.path.hasSuffix("/pages") ? PixivFixtures.pages(workID: 11, count: 4) : Self.ranking(url)
        }
        let store = store(transport)
        var announced: [URL] = []
        store.onThumbnailsAvailable = { announced += $0 }
        store.apply(PixivQuery())
        try await waitUntil { store.hasLoaded }
        XCTAssertEqual(announced.count, 3, "every thumbnail on the page, filtered or not")

        let first = try XCTUnwrap(store.work(id: "11"))
        store.select(first)
        XCTAssertNil(store.selectedPages)
        try await waitUntil { store.selectedPages != nil }
        XCTAssertEqual(store.selectedPageList?.count, 4)
        XCTAssertEqual(announced.count, 7, "the pages' previews are announced too")

        store.selectPage(3)
        XCTAssertEqual(store.selectedPage, 3)
        store.selectPage(9)
        XCTAssertEqual(store.selectedPage, 3)

        store.select(try XCTUnwrap(store.work(id: "12")))
        XCTAssertEqual(store.selectedPage, 0)
        try await waitUntil { store.selectedPages != nil }
        store.select(first)
        XCTAssertEqual(store.selectedPageList?.count, 4, "known pages come back at once")
        XCTAssertEqual(transport.requests.filter { $0.path.hasSuffix("/pages") }.count, 2)
    }

    func testADownloadedWorkStaysReachableAfterPagingAway() async throws {
        let transport = PixivFixtureTransport { url in
            url.path.hasSuffix("/pages") ? PixivFixtures.pages(workID: 11, count: 1)
                : url.host == "i.pximg.net" ? PixivFixtures.imageBytes("jpg") : Self.ranking(url)
        }
        let store = store(transport)
        store.apply(PixivQuery())
        try await waitUntil { store.hasLoaded }
        let work = try XCTUnwrap(store.work(id: "11"))

        store.requestDownload(work, page: 0)
        store.requestDownload(work, page: 5)
        store.loadPage(2)
        try await waitUntil { store.page == 2 }

        XCTAssertEqual(store.downloads.downloads.map(\.id), ["pixiv-11-p0"], "a page the work lacks is ignored")
        XCTAssertEqual(store.work(id: "11"), work)
        try await waitUntil { store.downloads.downloads.first?.isPending == false }
        await store.downloads.shutdown()
    }

    // MARK: - Signing in

    func testSigningInKeepsASessionPixivConfirmsAndReloadsTheListingWithIt() async throws {
        let transport = Self.member()
        let sessions = PixivMemorySessionStore()
        let store = store(transport, sessions: sessions)
        store.apply(PixivQuery())
        try await waitUntil { store.hasLoaded }

        store.signIn { PixivFixtures.session }
        XCTAssertTrue(store.isSigningIn)
        try await waitUntil { !store.isSigningIn && !store.isLoading && store.account != nil }

        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(store.account, PixivAccount(id: "31415926", name: "Tester", showsR18: true))
        XCTAssertNil(store.accountMessage)
        XCTAssertEqual(sessions.session, PixivFixtures.session)
        XCTAssertEqual(transport.requests.map(\.path), ["/ranking.php", "/touch/ajax/user/self/status", "/ranking.php"])
        XCTAssertEqual(transport.sessions, [nil, PixivFixtures.session, PixivFixtures.session])
    }

    func testASessionPixivDoesNotRecogniseIsNeitherUsedNorKept() async throws {
        let transport = Self.member()
        let sessions = PixivMemorySessionStore()
        let store = store(transport, sessions: sessions)

        store.signIn { PixivFixtures.otherSession }
        try await waitUntil { !store.isSigningIn }

        XCTAssertFalse(store.isSignedIn)
        XCTAssertNil(store.account)
        XCTAssertNil(sessions.session)
        XCTAssertEqual(store.accountMessage, PixivFailure(code: .signedOut).localizedDescription)

        store.signIn { "PHPSESSID=\(PixivFixtures.session)" }
        try await waitUntil { !store.isSigningIn }
        XCTAssertFalse(store.isSignedIn, "only a bare session value is accepted")
        XCTAssertEqual(transport.requests.count, 1, "a malformed value is never sent")
    }

    func testClosingTheSignInWindowChangesNothing() async throws {
        let transport = Self.member()
        let store = store(transport)

        store.signIn { nil }
        try await waitUntil { !store.isSigningIn }

        XCTAssertFalse(store.isSignedIn)
        XCTAssertNil(store.accountMessage)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAKeychainThatRefusesTheSessionStillSignsInUntilQuit() async throws {
        let sessions = PixivMemorySessionStore()
        sessions.refusesToSave = true
        let store = store(Self.member(), sessions: sessions)

        store.signIn { PixivFixtures.session }
        try await waitUntil { !store.isSigningIn }

        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(store.accountMessage, PixivFailure(code: .notSaved).localizedDescription)
        XCTAssertNil(sessions.session)
    }

    func testR18WorksAreAskedForOnlyWhileSignedInWithMatureTicked() async throws {
        let transport = Self.member()
        let store = store(transport)
        let r18 = PixivQuery(ranking: .dailyR18, ratings: [.everyone, .mature])

        store.apply(r18)
        XCTAssertEqual(store.query.ranking, .daily, "signed out, an R-18 ranking falls back to all ages")
        XCTAssertEqual(store.query.ratings, [.everyone])
        try await waitUntil { store.hasLoaded }
        XCTAssertEqual(mode(of: transport.requests.last), "daily")

        store.signIn { PixivFixtures.session }
        try await waitUntil { store.account != nil && !store.isLoading }
        store.apply(r18)
        try await waitUntil { store.committedQuery?.ranking == .dailyR18 && !store.isLoading }

        XCTAssertEqual(mode(of: transport.requests.last), "daily_r18")
        XCTAssertEqual(transport.sessions.last, PixivFixtures.session)
        XCTAssertEqual(store.works.map(\.rating), [.mature, .mature, .mature])
    }

    func testLoggingOutForgetsTheSessionAndEverythingR18() async throws {
        let transport = Self.member()
        let sessions = PixivMemorySessionStore()
        let store = store(transport, sessions: sessions)
        store.signIn { PixivFixtures.session }
        try await waitUntil { store.account != nil }
        store.apply(PixivQuery(ranking: .weeklyR18, ratings: [.mature]))
        try await waitUntil { store.committedQuery?.ranking == .weeklyR18 && !store.isLoading }
        store.select(try XCTUnwrap(store.works.first))
        XCTAssertEqual(store.selectedWork?.rating, .mature)
        XCTAssertEqual(store.works.count, 3)

        store.signOut()

        XCTAssertFalse(store.isSignedIn)
        XCTAssertNil(store.account)
        XCTAssertNil(sessions.session)
        XCTAssertNil(store.selectedWork, "an R-18 work does not stay on show")
        XCTAssertTrue(store.works.isEmpty, "R-18 tiles leave at once, before the reload answers")
        XCTAssertEqual(store.hiddenCount, 3)
        XCTAssertEqual(store.query.ranking, .weekly)
        XCTAssertEqual(store.query.ratings, [])
        try await waitUntil { store.committedQuery?.ranking == .weekly && !store.isLoading }
        XCTAssertEqual(mode(of: transport.requests.last), "weekly")
        XCTAssertNil(transport.sessions.last ?? nil)
    }

    func testASavedSessionIsTakenUpAndOnePixivEndedIsDropped() async throws {
        let kept = PixivMemorySessionStore(PixivFixtures.session)
        let store = store(Self.member(), sessions: kept)
        XCTAssertFalse(store.isSignedIn, "nothing is read before restoreSession()")
        store.restoreSession()
        try await waitUntil { store.account != nil }
        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(kept.session, PixivFixtures.session)

        let ended = PixivMemorySessionStore(PixivFixtures.otherSession)
        let expired = self.store(Self.member(), sessions: ended)
        expired.restoreSession()
        try await waitUntil { expired.accountMessage != nil }
        XCTAssertFalse(expired.isSignedIn)
        XCTAssertNil(ended.session)
        XCTAssertEqual(expired.accountMessage, PixivFailure(code: .signedOut).localizedDescription)
    }

    func testAnR18RefusalChecksWhetherPixivEndedTheSession() async throws {
        let ended = LockedFlag()
        let transport = Self.member(ended: ended)
        let sessions = PixivMemorySessionStore()
        let store = store(transport, sessions: sessions)
        store.signIn { PixivFixtures.session }
        try await waitUntil { store.account != nil }

        ended.value = true
        store.apply(PixivQuery(ranking: .dailyR18, ratings: [.everyone, .mature]))
        try await waitUntil { store.accountMessage != nil }

        XCTAssertFalse(store.isSignedIn)
        XCTAssertNil(sessions.session)
        XCTAssertEqual(store.accountMessage, PixivFailure(code: .signedOut).localizedDescription)
        try await waitUntil { store.committedQuery?.ranking == .daily && !store.isLoading }
        XCTAssertNil(store.errorMessage, "the all-ages ranking loads in its place")
    }
}
