import Foundation

/// App-owned preferences. An explicitly named test suite isolates a launched
/// client as well as stores created inside it; system-wide preferences stay
/// with their existing readers.
enum ClientPreferences {
    static let suiteEnvironmentKey = "WALLPAPER_MACHINE_DEFAULTS_SUITE"

    static var defaults: UserDefaults {
        resolve(environment: ProcessInfo.processInfo.environment)
    }

    static var domainName: String {
        domainName(environment: ProcessInfo.processInfo.environment)
    }

    static func resolve(environment: [String: String]) -> UserDefaults {
        guard let suite = suiteName(environment: environment) else { return .standard }
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("The explicitly requested preferences suite could not be opened.")
        }
        return defaults
    }

    static func domainName(environment: [String: String]) -> String {
        suiteName(environment: environment) ?? Bundle.main.bundleIdentifier ?? "app.wallpapermachine"
    }

    private static func suiteName(environment: [String: String]) -> String? {
        guard let name = environment[suiteEnvironmentKey], !name.isEmpty else { return nil }
        return name
    }
}
