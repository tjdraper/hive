import AppKit

/// The standard About panel, with the notices the licenses of bundled third-party software require.
@MainActor
enum AboutPanel {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
    }

    /// Built here rather than left to a `Credits.rtf`, whose text keeps a fixed color and turns
    /// unreadable in dark mode.
    private static func credits() -> NSAttributedString {
        let notices = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return NSAttributedString(string: notices, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }
}
