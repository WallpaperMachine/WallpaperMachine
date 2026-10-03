import Foundation

/// The content lifecycle of one host-owned surface, separate from its assignment.
struct HostWallpaperState: Equatable, Sendable {
    enum Kind: String, Sendable { case web, nativeVideo }
    enum Phase: String, Sendable { case loading, ready, failed, closed }

    var kind: Kind
    var displayID: UInt32
    var wallpaperID: String
    var startupRevision: UInt64
    var nativeAdmissionKey: UInt64?
    var phase: Phase
    var message: String?

    var key: String { "\(kind.rawValue):\(displayID)" }
}
