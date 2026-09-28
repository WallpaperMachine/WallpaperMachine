import Foundation

/// The pixiv tab's share of the panel: its snapshot section and the actions its page sends.
@MainActor
extension WebPanelController {
  func pixivSnapshot() -> [String: Any] {
    let null = NSNull()
    let installed = Self.installedPixivPages(in: store.librarySnapshot.wallpapers.map(\.id))
    let query = pixiv.query
    var selected: Any = null
    if let work = pixiv.selectedWork {
      var row = Self.pixivWork(work, installed: installed[work.id] ?? [])
      let index = pixiv.selectedPage
      let page = pixiv.selectedPageList?.first { $0.index == index }
      row["page"] = index
      row["pageCount"] = pixiv.pageCount(of: work)
      row["pagesLoading"] = pixiv.selectedPages == nil
      if case .failure(let failure) = pixiv.selectedPages {
        row["pagesError"] = failure.localizedDescription
      }
      if page?.previewURL != nil, let preview = Self.pixivAddress("\(work.id)-p\(index)") {
        row["preview"] = preview
      }
      row["pageWidth"] = page?.width ?? (index == 0 ? work.width : 0)
      row["pageHeight"] = page?.height ?? (index == 0 ? work.height : 0)
      row["libraryID"] = work.libraryID(page: index)
      selected = row
    }
    var searching = false
    if case .search = (pixiv.committedQuery ?? query).listing { searching = true }
    let account = pixiv.account
    return [
      "account": [
        "signedIn": pixiv.isSignedIn, "signingIn": pixiv.isSigningIn,
        "name": account?.name as Any? ?? null, "id": account?.id as Any? ?? null,
        "showsR18": account?.showsR18 as Any? ?? null, "message": pixiv.accountMessage as Any? ?? null,
      ],
      "query": [
        "text": query.text, "ranking": query.ranking.rawValue, "order": query.order.rawValue,
        "orientation": query.orientation.rawValue, "minimumSize": query.minimumSize.rawValue,
        "hideAI": query.hidesAIGenerated,
        "ratings": PixivQuery.offeredRatings.filter(query.ratings.contains).map(\.rawValue),
      ],
      "searching": searching,
      "items": pixiv.works.map { Self.pixivWork($0, installed: installed[$0.id] ?? []) },
      "hidden": pixiv.hiddenCount, "page": pixiv.page, "totalPages": pixiv.totalPages,
      "totalCount": pixiv.totalCount, "loading": pixiv.isLoading, "loaded": pixiv.hasLoaded,
      "error": pixiv.errorMessage as Any? ?? null,
      "selectedID": pixiv.selectedWork?.id as Any? ?? null, "selected": selected,
      "downloads": pixiv.downloads.downloads.map(Self.pixivDownload),
    ]
  }

  /// The pixiv actions; false when `action` is not one of them.
  func performPixiv(_ action: String, request: WebPanelRequest) throws -> Bool {
    switch action {
    case "pixivSearch":
      let text = try request.string("text")
      guard text.count <= 256,
        let ranking = PixivRanking(rawValue: try request.string("ranking")),
        let order = PixivSearchOrder(rawValue: try request.string("order")),
        let orientation = PixivOrientation(rawValue: try request.string("orientation")),
        let minimumSize = PixivMinimumSize(rawValue: try request.string("minimumSize")),
        let names = request.body["ratings"] as? [String], names.count <= PixivRating.allCases.count
      else { throw WebPanelRequest.invalid }
      var ratings = Set<PixivRating>()
      for name in names {
        guard let rating = PixivRating(rawValue: name), PixivQuery.offeredRatings.contains(rating) else {
          throw WebPanelRequest.invalid
        }
        ratings.insert(rating)
      }
      pixiv.apply(
        PixivQuery(
          text: text, ranking: ranking, order: order, orientation: orientation, minimumSize: minimumSize,
          hidesAIGenerated: try request.boolean("hideAI"), ratings: ratings),
        refresh: try request.boolean("refresh"))
    case "pixivPage":
      pixiv.loadPage(Int(try request.number("page", range: 1...Double(PixivService.maxPages))))
    case "pixivRetry":
      pixiv.retry()
    case "pixivSelect":
      pixiv.select(try pixivWork(request))
    case "pixivSelectPage":
      guard let work = pixiv.selectedWork, work.id == (try request.string("id")) else {
        throw WebPanelRequest.invalid
      }
      pixiv.selectPage(Int(try request.number("page", range: 0...Double(pixiv.pageCount(of: work) - 1))))
    case "pixivRetryPages":
      pixiv.retrySelectedPages()
    case "pixivDownload":
      let work = try pixivWork(request)
      let page = Int(try request.number("page", range: 0...Double(max(0, pixiv.pageCount(of: work) - 1))))
      pixiv.requestDownload(work, page: page)
    case "pixivCancel":
      pixiv.downloads.cancel(try request.string("id"))
    case "pixivRetryDownload":
      guard pixiv.downloads.retry(try request.string("id")) else { throw WebPanelRequest.invalid }
    case "pixivClearDownloads":
      pixiv.downloads.clearFinished()
    case "pixivSignIn":
      if pixiv.isSigningIn {
        PixivSignInWindowController.bringToFront()
      } else if !pixiv.isSignedIn {
        pixiv.signIn(obtainingSessionWith: signInToPixiv ?? PixivSignInWindowController.obtainSession)
      }
    case "pixivSignOut":
      pixiv.signOut()
    default:
      return false
    }
    return true
  }

  private func pixivWork(_ request: WebPanelRequest) throws -> PixivWork {
    guard let work = pixiv.work(id: try request.string("id")) else { throw WebPanelRequest.invalid }
    return work
  }

  /// Pages of pixiv works that are in the library, by work id, read off the wallpaper ids the
  /// packager gives them (`pixiv-<work>-p<page>`).
  static func installedPixivPages(in ids: [String]) -> [String: [Int]] {
    var pages: [String: [Int]] = [:]
    for id in ids where id.hasPrefix("pixiv-") {
      let parts = id.split(separator: "-", omittingEmptySubsequences: false)
      guard parts.count == 3, PixivWork.isValidID(String(parts[1])), parts[2].first == "p",
        let page = Int(parts[2].dropFirst()), page >= 0, String(page) == parts[2].dropFirst()
      else { continue }
      pages[String(parts[1]), default: []].append(page)
    }
    return pages.mapValues { $0.sorted() }
  }

  static func pixivWork(_ work: PixivWork, installed: [Int]) -> [String: Any] {
    let null = NSNull()
    return [
      "id": work.id, "title": work.title, "author": work.authorName,
      "thumbnail": work.thumbnailURL.flatMap { _ in pixivAddress(work.id) } as Any? ?? null,
      "width": work.width, "height": work.height, "pages": work.pageCount,
      "rating": work.rating.rawValue, "ai": work.aiGenerated as Any? ?? null,
      "rank": work.rank as Any? ?? null, "tags": work.tags, "url": work.artworkURL.absoluteString,
      "installed": installed,
    ]
  }

  static func pixivDownload(_ job: PixivDownload) -> [String: Any] {
    let null = NSNull()
    let status: String
    switch job.status {
    case .waiting: status = "waiting"
    case .downloading: status = "downloading"
    case .installing: status = "installing"
    case .finished: status = "finished"
    case .cancelled: status = "cancelled"
    case .failed: status = "failed"
    }
    return [
      "id": job.id, "workID": job.work.id, "page": job.pageIndex, "title": job.work.title,
      "status": status, "pending": job.isPending, "progress": job.progress as Any? ?? null,
      "received": job.bytesReceived, "expected": job.bytesExpected as Any? ?? null,
      "error": job.errorMessage as Any? ?? null,
    ]
  }

  /// `mwe-ui://pixiv-thumbnail/<key>`, the panel-local address `WebPanelAssets` serves the image
  /// behind `key` from: a work's thumbnail by its id, a page's preview by `<id>-p<page>`.
  static func pixivAddress(_ key: String) -> String? {
    var components = URLComponents()
    components.scheme = "mwe-ui"
    components.host = "pixiv-thumbnail"
    components.path = "/" + key
    return components.url?.absoluteString
  }
}
