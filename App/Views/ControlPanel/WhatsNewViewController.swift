import AppKit

/// A native, nonmodal reading window with a choice of release-note translation: the releases an
/// update brought, or the whole bundled history when Settings › About asks for it.
@MainActor
final class WhatsNewViewController: NSViewController {
    static let defaultContentSize = NSSize(width: 760, height: 800)
    private let announcement: WhatsNewStore.Announcement
    private let preferences: WhatsNewStore
    private let close: () -> Void
    private let initialLanguage: AppLanguage
    private let bannerImage: (AppReleaseHistory.Banner) -> NSImage?
    /// Turns off the post-update window for good and closes it. Absent from the history window.
    private(set) var dontShowAgainButton: NSButton?
    /// Adds and removes the releases before the announced ones. Absent when there are none.
    private(set) var earlierReleasesButton: NSButton?
    private(set) var notesView: NSTextView!
    private(set) var languageControl: NSSegmentedControl!
    /// The current release's banner, when it has one the bundle can show.
    private(set) var bannerView: NSImageView?
    /// Each translation's banner and its picture, loaded once for this announcement.
    private var banners: [AppReleaseHistory.Language: (banner: AppReleaseHistory.Banner, image: NSImage)] = [:]
    private var bannerAspect: NSLayoutConstraint?
    private(set) var showsEarlierReleases = false

    init(announcement: WhatsNewStore.Announcement, preferences: WhatsNewStore,
         initialLanguage: AppLanguage,
         bannerImage: @escaping (AppReleaseHistory.Banner) -> NSImage? = WhatsNewViewController.bundledBanner,
         close: @escaping () -> Void) {
        self.announcement = announcement
        self.preferences = preferences
        self.close = close
        self.initialLanguage = initialLanguage
        self.bannerImage = bannerImage
        super.init(nibName: nil, bundle: nil)
    }

    static func bundledBanner(_ banner: AppReleaseHistory.Banner) -> NSImage? {
        Bundle.main.url(forResource: banner.fileName, withExtension: nil,
                        subdirectory: AppReleaseHistory.Banner.directory)
            .flatMap(NSImage.init(contentsOf:))
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: Self.defaultContentSize))
        let isHistory = announcement.kind == .history
        let title = NSTextField(labelWithString: isHistory ? String(localized: "Release History") : String(localized: "What’s New"))
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let version = NSTextField(labelWithString: "WallpaperMachine \(announcement.currentVersion)")
        version.font = .systemFont(ofSize: 15, weight: .medium)
        let detail: String
        if isHistory {
            detail = String(localized: "Every release up to this version")
        } else if let previous = announcement.previousVersion {
            detail = String(localized: "Changes since version \(previous)")
        } else {
            detail = String(localized: "Changes in this version")
        }
        let subtitle = NSTextField(wrappingLabelWithString: detail)
        subtitle.textColor = .secondaryLabelColor
        let header = NSStackView(views: [title, version, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 6

        languageControl = NSSegmentedControl(
            labels: AppReleaseHistory.Language.allCases.map(\.name), trackingMode: .selectOne,
            target: self, action: #selector(changeLanguage))
        languageControl.selectedSegment = AppReleaseHistory.Language(appLanguage: initialLanguage).rawValue
        languageControl.setAccessibilityLabel(String(localized: "Release notes language"))

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        notesView = NSTextView()
        notesView.isEditable = false
        notesView.isSelectable = true
        notesView.drawsBackground = false
        notesView.isHorizontallyResizable = false
        notesView.isVerticallyResizable = true
        notesView.autoresizingMask = [.width]
        notesView.textContainerInset = NSSize(width: 0, height: 8)
        notesView.textContainer?.widthTracksTextView = true
        notesView.textContainer?.lineFragmentPadding = 0
        notesView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        updateNotes()
        notesView.setAccessibilityLabel(String(localized: "Release notes"))
        scroll.documentView = notesView

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 12
        if !isHistory, !announcement.earlierReleases.isEmpty {
            let earlier = NSButton(title: String(localized: "Show Earlier Releases"), target: self,
                                   action: #selector(toggleEarlierReleases))
            footer.addView(earlier, in: .leading)
            earlierReleasesButton = earlier
        }
        if !isHistory {
            let dontShow = NSButton(title: String(localized: "Don’t Show Again"), target: self,
                                    action: #selector(dontShowAgain))
            dontShow.toolTip = String(localized: "Turn it back on in Settings › About.")
            footer.addView(dontShow, in: .trailing)
            dontShowAgainButton = dontShow
        }
        let closeButton = NSButton(title: String(localized: "Close"), target: self, action: #selector(closeWindow))
        closeButton.keyEquivalent = "\r"
        footer.addView(closeButton, in: .trailing)
        let divider = NSBox()
        divider.boxType = .separator
        for child in [header, languageControl!, scroll, divider, footer] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        // Only the version being announced shows its banner: older ones are history.
        if let current = announcement.releases.first {
            var loaded: [String: NSImage] = [:]
            var attempted: Set<String> = []
            for language in AppReleaseHistory.Language.allCases {
                guard let banner = current.banner(language: language) else { continue }
                if attempted.insert(banner.fileName).inserted { loaded[banner.fileName] = bannerImage(banner) }
                if let image = loaded[banner.fileName], image.size.width > 0, image.size.height > 0 {
                    banners[language] = (banner, image)
                }
            }
        }
        if !banners.isEmpty {
            let bannerView = NSImageView()
            bannerView.imageScaling = .scaleProportionallyUpOrDown
            bannerView.wantsLayer = true
            bannerView.layer?.cornerRadius = 10
            bannerView.layer?.masksToBounds = true
            // The picture's pixel size is not a size the window must make room for.
            for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
                bannerView.setContentCompressionResistancePriority(.defaultLow, for: axis)
                bannerView.setContentHuggingPriority(.defaultLow, for: axis)
            }
            bannerView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bannerView)
            let fill = bannerView.trailingAnchor.constraint(equalTo: header.trailingAnchor)
            fill.priority = .defaultHigh
            NSLayoutConstraint.activate([
                fill,
                bannerView.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
                bannerView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
                // A wide window must not grow the banner until it crowds out the notes.
                bannerView.widthAnchor.constraint(lessThanOrEqualToConstant: Self.defaultContentSize.width - 48),
                header.topAnchor.constraint(equalTo: bannerView.bottomAnchor, constant: 20),
            ])
            self.bannerView = bannerView
            updateBanner()
        } else {
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 24).isActive = true
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            languageControl.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            languageControl.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: languageControl.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -16),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),
            footer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
        ])
    }

    @objc private func changeLanguage() {
        updateNotes()
        updateBanner()
        notesView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    private var selectedLanguage: AppReleaseHistory.Language {
        AppReleaseHistory.Language(rawValue: languageControl.selectedSegment) ?? .english
    }

    /// The history window shows everything; the update window adds the earlier releases on request.
    private var shownReleases: [AppReleaseHistory.Entry] {
        announcement.kind == .history || showsEarlierReleases
            ? announcement.releases + announcement.earlierReleases : announcement.releases
    }

    private func updateNotes() {
        notesView.textStorage?.setAttributedString(Self.notesText(shownReleases, language: selectedLanguage))
    }

    /// Resolve the selected banner after loading, so an unreadable file also falls back.
    private func updateBanner() {
        guard let bannerView,
              let shown = selectedLanguage.bannerFallbacks.lazy.compactMap({ self.banners[$0] }).first else { return }
        bannerView.image = shown.image
        bannerView.setAccessibilityLabel(shown.banner.description)
        let ratio = shown.image.size.height / shown.image.size.width
        guard bannerAspect?.multiplier != ratio else { return }
        bannerAspect?.isActive = false
        bannerAspect = bannerView.heightAnchor.constraint(equalTo: bannerView.widthAnchor, multiplier: ratio)
        bannerAspect?.isActive = true
    }

    @objc private func toggleEarlierReleases() {
        // The announced releases render first and unchanged, so their length is where the rest begin.
        let announcedLength = notesView.string.utf16.count
        showsEarlierReleases.toggle()
        earlierReleasesButton?.title = showsEarlierReleases
            ? String(localized: "Hide Earlier Releases") : String(localized: "Show Earlier Releases")
        updateNotes()
        if showsEarlierReleases { scrollNotes(to: announcedLength) }
    }

    /// Brings the line at `location` to the top of the notes.
    private func scrollNotes(to location: Int) {
        guard let layout = notesView.layoutManager, let container = notesView.textContainer,
              location < notesView.string.utf16.count else { return }
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: location, length: 1),
                                       actualCharacterRange: nil)
        let line = layout.boundingRect(forGlyphRange: glyphs, in: container)
        notesView.scroll(NSPoint(x: 0, y: line.minY + notesView.textContainerOrigin.y))
    }

    @objc private func dontShowAgain() {
        preferences.isSuppressed = true
        close()
    }

    @objc private func closeWindow() { close() }

    private static func notesText(_ releases: [AppReleaseHistory.Entry],
                                  language: AppReleaseHistory.Language) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "")
        func paragraph(before: CGFloat, after: CGFloat, indent: CGFloat = 0) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = after
            style.lineSpacing = 3
            if indent > 0 {
                // A hanging indent: wrapped lines start under the text, not under the bullet.
                style.tabStops = [NSTextTab(textAlignment: .natural, location: indent)]
                style.defaultTabInterval = indent
                style.headIndent = indent
            }
            return style
        }
        func append(_ value: String, size: CGFloat = 14, weight: NSFont.Weight = .regular,
                    color: NSColor = .labelColor, before: CGFloat = 0, after: CGFloat = 6) {
            text.append(NSAttributedString(string: value + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: paragraph(before: before, after: after),
            ]))
        }
        func bullet(_ value: String, highlighted: Bool) {
            let style = paragraph(before: 0, after: highlighted ? 8 : 6, indent: 18)
            let font = NSFont.systemFont(ofSize: highlighted ? 15 : 14, weight: highlighted ? .medium : .regular)
            text.append(NSAttributedString(string: highlighted ? "\u{2726}\t" : "\u{2022}\t", attributes: [
                .font: font,
                .foregroundColor: highlighted ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
                .paragraphStyle: style,
            ]))
            text.append(NSAttributedString(string: value + "\n", attributes: [
                .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style,
            ]))
        }
        for release in releases {
            append(release.version.display, size: 20, weight: .semibold, before: text.length == 0 ? 0 : 24)
            let notes = release.notes(language: language)
            for section in notes.sections {
                let highlighted = section.isHighlights
                if !section.title.isEmpty {
                    append(section.title, size: highlighted ? 15 : 14, weight: .semibold,
                           color: highlighted ? .controlAccentColor : .labelColor, before: 12)
                }
                for item in section.items {
                    if section.isList { bullet(item, highlighted: highlighted) } else { append(item) }
                }
            }
        }
        return text
    }
}
