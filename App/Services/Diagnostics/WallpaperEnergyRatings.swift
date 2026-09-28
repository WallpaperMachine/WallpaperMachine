import Foundation

/// The settings a wallpaper's energy was measured under. A rating is only comparable
/// with measurements taken under the same ones.
struct WallpaperEnergyConditions: Codable, Equatable, Sendable {
  /// Displays showing the wallpaper.
  var displays: Int
  /// Global frame-rate ceiling in force, the battery one included; nil is no limit.
  var frameRateCap: UInt32?
  /// Render scale in force, rounded to hundredths.
  var renderScale: Double
}

/// One wallpaper, alone on every display that is presenting, under known conditions.
struct WallpaperEnergyContext: Equatable, Sendable {
  var wallpaperID: String
  var conditions: WallpaperEnergyConditions

  /// Energy is charged to the whole app, so it can be attributed only while exactly one
  /// wallpaper is presenting. Displays suspended on their own (covered by windows) do
  /// not count; a display with no wallpaper does not either.
  static func resolve(
    assignments: [(display: String, wallpaper: String)], suspendedDisplays: Set<UInt32>,
    frameRateCap: UInt32?, renderScale: Float
  ) -> WallpaperEnergyContext? {
    let presenting = assignments.filter { assignment in
      !assignment.wallpaper.isEmpty
        && !(UInt32(assignment.display).map(suspendedDisplays.contains) ?? false)
    }
    let ids = Set(presenting.map(\.wallpaper))
    guard ids.count == 1, let id = ids.first else { return nil }
    return WallpaperEnergyContext(
      wallpaperID: id,
      conditions: WallpaperEnergyConditions(
        displays: presenting.count, frameRateCap: frameRateCap,
        renderScale: (Double(renderScale) * 100).rounded() / 100))
  }
}

/// Mean power the app drew while one wallpaper played under `conditions`.
struct WallpaperEnergyRating: Codable, Equatable, Sendable {
  var milliwatts: Double
  /// Measured time behind the mean.
  var seconds: Double
  var conditions: WallpaperEnergyConditions
  var updated: Date

  var level: EnergyLevel { EnergyLevel(milliwatts: milliwatts) }
}

/// Energy ratings per wallpaper id, kept in one small JSON file.
///
/// A measurement under different conditions replaces the rating instead of being
/// averaged in, so a rating always describes the settings it names. Writes are
/// batched: the file is saved when a rating first becomes shown or changes level,
/// at most every `saveInterval` otherwise, and on `flush()`.
@MainActor
final class WallpaperEnergyRatings {
  /// Measured time before a rating is shown. Two minutes is four or more intervals,
  /// enough to ride out a scene's loading work and the kernel's batched GPU energy.
  static let minimumSeconds = 120.0
  /// Past this much measured time a new interval keeps the same weight, so a rating
  /// follows a wallpaper whose cost changed (an update, a renderer change).
  static let weightCapSeconds = 1_800.0
  static let saveInterval: TimeInterval = 600

  private(set) var entries: [String: WallpaperEnergyRating]
  private let file: URL
  private var lastSave: Date?
  private var dirty = false

  init(file: URL) {
    self.file = file
    do {
      entries =
        FileManager.default.fileExists(atPath: file.path)
        ? try JSONDecoder().decode([String: WallpaperEnergyRating].self, from: Data(contentsOf: file))
        : [:]
    } catch {
      // A rating is a measurement that is taken again, not user data worth failing over.
      AppLog.error("Energy ratings could not be read and start empty: \(error.localizedDescription)")
      entries = [:]
    }
  }

  /// Nil until the wallpaper has been measured for `minimumSeconds`.
  func rating(for id: String) -> WallpaperEnergyRating? {
    guard let entry = entries[id], entry.seconds >= Self.minimumSeconds else { return nil }
    return entry
  }

  func record(
    _ context: WallpaperEnergyContext, milliwatts: Double, seconds: Double, now: Date = Date()
  ) {
    guard seconds > 0, milliwatts.isFinite, milliwatts >= 0 else { return }
    let id = context.wallpaperID
    let shownLevel = rating(for: id)?.level
    var entry = WallpaperEnergyRating(
      milliwatts: milliwatts, seconds: seconds, conditions: context.conditions, updated: now)
    if let existing = entries[id], existing.conditions == context.conditions {
      let weight = min(existing.seconds, Self.weightCapSeconds)
      entry.milliwatts = (existing.milliwatts * weight + milliwatts * seconds) / (weight + seconds)
      entry.seconds = existing.seconds + seconds
    }
    entries[id] = entry
    dirty = true
    let due = lastSave.map { now.timeIntervalSince($0) >= Self.saveInterval } ?? true
    if due || rating(for: id)?.level != shownLevel { save(now: now) }
  }

  func flush() {
    if dirty { save(now: Date()) }
  }

  /// What the panel shows for one wallpaper, or nil when it has no rating yet.
  func snapshot(for id: String) -> [String: Any]? {
    guard let rating = rating(for: id) else { return nil }
    return [
      "level": rating.level.rawValue,
      "milliwatts": rating.milliwatts,
      "displays": rating.conditions.displays,
      "frameRateCap": rating.conditions.frameRateCap.map { Int($0) } as Any? ?? NSNull(),
      "renderScale": rating.conditions.renderScale,
    ]
  }

  private func save(now: Date) {
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(entries).write(to: file, options: .atomic)
      dirty = false
      lastSave = now
    } catch {
      AppLog.error("Energy ratings could not be saved: \(error.localizedDescription)")
    }
  }
}

/// Measures the app's energy in the background and credits it to the wallpaper playing.
///
/// Every `interval` it asks `context` what is on screen. Nil (paused, suspended, more
/// than one wallpaper, the panel open, a download running) takes no sample and breaks
/// the chain. Otherwise it samples the coalition counters off the main thread, and an
/// interval whose two ends saw the same context and whose GPU was not contended is
/// recorded. Anything that changes presentation in between should call `invalidate()`,
/// since a pause and resume inside one interval leaves both ends looking the same.
@MainActor
final class WallpaperEnergyRecorder {
  /// One sample costs about 3 ms of kernel calls; every 30 s that is 0.01 % of a core.
  nonisolated static let defaultInterval: Duration = .seconds(30)

  private let source: EnergyUsageSource?
  private let ratings: WallpaperEnergyRatings
  private let interval: Duration
  private let context: @MainActor () -> WallpaperEnergyContext?
  private var previous: (sample: EnergyUsageSample, context: WallpaperEnergyContext)?
  private var task: Task<Void, Never>?

  var isRunning: Bool { task != nil }

  init(
    source: EnergyUsageSource?, ratings: WallpaperEnergyRatings,
    interval: Duration = defaultInterval,
    context: @escaping @MainActor () -> WallpaperEnergyContext?
  ) {
    self.source = source
    self.ratings = ratings
    self.interval = interval
    self.context = context
  }

  func start() {
    guard task == nil, let source else { return }
    let interval = interval
    task = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: interval)
        guard !Task.isCancelled, let self else { return }
        guard let context = self.context() else {
          self.previous = nil
          continue
        }
        let sample = await Task.detached(priority: .utility) { source.sample() }.value
        guard !Task.isCancelled else { return }
        self.record(sample, context: context)
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
    previous = nil
    ratings.flush()
  }

  /// Presentation changed; the interval in progress must not be credited to anyone.
  func invalidate() {
    previous = nil
  }

  /// Credits the interval since the previous sample when both ends agree. Nil means the
  /// counters could not be read.
  func record(_ sample: EnergyUsageSample?, context: WallpaperEnergyContext) {
    guard let sample else {
      previous = nil
      return
    }
    defer { previous = (sample, context) }
    guard let previous, previous.context == context else { return }
    let reading = EnergyUsageReading.between(previous.sample, sample)
    guard reading.isComparable else { return }
    ratings.record(context, milliwatts: reading.totalMilliwatts, seconds: reading.seconds)
  }
}
