import AppKit

/// A native, nonmodal reading window; both translations remain visible without a language switch.
@MainActor
final class WhatsNewViewController: NSViewController {
    private let announcement: WhatsNewStore.Announcement
    private let preferences: WhatsNewStore
    private let close: () -> Void
    private(set) var suppressionCheckbox: NSButton!
    private(set) var notesView: NSTextView!

    init(announcement: WhatsNewStore.Announcement, preferences: WhatsNewStore, close: @escaping () -> Void) {
        self.announcement = announcement
        self.preferences = preferences
        self.close = close
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()
        let title = NSTextField(labelWithString: String(localized: "What’s New"))
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let version = NSTextField(labelWithString: "WallpaperMachine \(announcement.currentVersion)")
        version.font = .systemFont(ofSize: 15, weight: .medium)
        let detail: String
        if let previous = announcement.previousVersion {
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
        notesView.textStorage?.setAttributedString(Self.notesText(announcement))
        notesView.setAccessibilityLabel(String(localized: "Release notes in English and Simplified Chinese"))
        scroll.documentView = notesView

        suppressionCheckbox = NSButton(
            checkboxWithTitle: String(localized: "Don’t show this window after updates"),
            target: self, action: #selector(changeSuppression))
        suppressionCheckbox.state = preferences.isSuppressed ? .on : .off
        suppressionCheckbox.setContentCompressionResistancePriority(.required, for: .horizontal)
        let closeButton = NSButton(title: String(localized: "Close"), target: self, action: #selector(closeWindow))
        closeButton.keyEquivalent = "\r"
        let divider = NSBox()
        divider.boxType = .separator
        for child in [header, scroll, divider, suppressionCheckbox!, closeButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -16),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            suppressionCheckbox.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),
            suppressionCheckbox.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            suppressionCheckbox.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            closeButton.centerYAnchor.constraint(equalTo: suppressionCheckbox.centerYAnchor),
            closeButton.leadingAnchor.constraint(greaterThanOrEqualTo: suppressionCheckbox.trailingAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor),
        ])
    }

    @objc private func changeSuppression() {
        preferences.isSuppressed = suppressionCheckbox.state == .on
    }

    @objc private func closeWindow() { close() }

    private static func notesText(_ announcement: WhatsNewStore.Announcement) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "")
        func append(_ value: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                    before: CGFloat = 0, after: CGFloat = 6) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacingBefore = before
            paragraph.paragraphSpacing = after
            paragraph.lineSpacing = 3
            text.append(NSAttributedString(string: value + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]))
        }
        for release in announcement.releases {
            append(release.version.display, size: 20, weight: .semibold, before: text.length == 0 ? 0 : 24)
            for (language, notes) in [("English", release.english), ("简体中文", release.chinese)] {
                append(language, size: 15, weight: .semibold, before: 12, after: 10)
                for section in notes.sections {
                    if !section.title.isEmpty { append(section.title, weight: .semibold, before: 8) }
                    for item in section.items { append(item) }
                }
            }
        }
        return text
    }
}
