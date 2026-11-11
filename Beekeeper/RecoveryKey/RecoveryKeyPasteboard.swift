import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

/// Copies a recovery key so it can be pasted into a password manager, marked so it isn't kept around
/// afterwards.
enum RecoveryKeyPasteboard {
    #if os(macOS)
    /// The marker clipboard managers honor and leave out of their history (http://nspasteboard.org).
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    #else
    private static let lifetime: TimeInterval = 5 * 60
    #endif

    static func copy(_ code: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, concealed], owner: nil)
        pasteboard.setString(code, forType: .string)
        pasteboard.setString(code, forType: concealed)
        #else
        // Local only, so Universal Clipboard doesn't hand it to the person's other devices.
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: code]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(lifetime)]
        )
        #endif
    }
}
