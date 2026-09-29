import Foundation

/// The bilingual release history shipped with this copy, never the newest remote release.
struct AppReleaseHistory {
    struct Entry: Equatable, Sendable {
        let version: SemanticVersion
        let english: ReleaseNotes
        let chinese: ReleaseNotes
    }

    enum InvalidHistory: Error {
        case missingResource, invalidVersion, duplicateVersion, missingTranslation
    }

    let entries: [Entry]

    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md") else {
            throw InvalidHistory.missingResource
        }
        try self.init(markdown: String(contentsOf: url, encoding: .utf8))
    }

    init(markdown: String) throws {
        var entries: [Entry] = []
        var version: SemanticVersion?
        var english = ""
        var chinese = ""
        var language = ""
        func finish() throws {
            guard let version else { return }
            guard !entries.contains(where: { $0.version == version }) else {
                throw InvalidHistory.duplicateVersion
            }
            guard let en = ReleaseNotes(version: version.display, body: english),
                  let zh = ReleaseNotes(version: version.display, body: chinese) else {
                throw InvalidHistory.missingTranslation
            }
            entries.append(Entry(version: version, english: en, chinese: zh))
        }
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                try finish()
                guard let token = line.dropFirst(3).split(separator: " ").first,
                      let parsed = SemanticVersion(String(token)) else {
                    throw InvalidHistory.invalidVersion
                }
                version = parsed
                english = ""
                chinese = ""
                language = ""
            } else if line == "### English" {
                language = "en"
            } else if line == "### 简体中文" {
                language = "zh-Hans"
            } else if version != nil {
                if language == "en" { english += line + "\n" }
                if language == "zh-Hans" { chinese += line + "\n" }
            }
        }
        try finish()
        self.entries = entries.sorted { $0.version > $1.version }
    }
}
