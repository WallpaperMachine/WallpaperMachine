import Foundation

/// Separate from the scene schema so an extension can answer even when it cannot decode it.
struct LockScreenExtensionRequest: Codable {
  static let fileName = "activation-request.json"
  var revision: String
}

struct LockScreenExtensionStatus: Codable {
  static let fileName = "extension-status.json"
  var revision: String
  var bundlePath: String
  var supportedVersion: Int
  var error: String?

  enum ConfigurationError: Error {
    case unsupportedVersion(Int)
  }

  /// Capture the request before loading; a late answer must retain its original revision.
  static func loadConfiguration(
    exchange: URL, bundleURL: URL,
    supportedVersion: Int = LockScreenConfiguration.supportedVersion,
    reportWriteFailure: (Error) -> Void
  ) throws -> LockScreenConfiguration {
    let decoder = JSONDecoder()
    let request = (try? Data(contentsOf: exchange.appendingPathComponent(LockScreenExtensionRequest.fileName)))
      .flatMap { try? decoder.decode(LockScreenExtensionRequest.self, from: $0) }
    var revision = request?.revision
    do {
      let data = try Data(contentsOf: exchange.appendingPathComponent(LockScreenConfiguration.fileName))
      // Check the envelope before decoding fields an older extension may not understand.
      struct Header: Decodable {
        var revision: String
        var version: Int
      }
      let header = try decoder.decode(Header.self, from: data)
      revision = header.revision
      guard header.version == supportedVersion else {
        throw ConfigurationError.unsupportedVersion(header.version)
      }
      let configuration = try decoder.decode(LockScreenConfiguration.self, from: data)
      record(error: nil)
      return configuration
    } catch {
      record(error: error.localizedDescription)
      throw error
    }

    func record(error: String?) {
      // The app publishes the manifest before the request. Ignore that brief transition.
      guard let request, revision == request.revision else { return }
      let status = Self(
        revision: request.revision, bundlePath: bundleURL.resolvingSymlinksInPath().path,
        supportedVersion: supportedVersion, error: error)
      do {
        try JSONEncoder().encode(status).write(
          to: exchange.appendingPathComponent(Self.fileName), options: .atomic)
      } catch { reportWriteFailure(error) }
    }
  }
}
