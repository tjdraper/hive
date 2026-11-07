import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Copies text the person needs on a server, and says so for a moment.
struct CopyButton: View {
    let text: String

    @State private var didCopy = false

    var body: some View {
        Button(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #else
            UIPasteboard.general.string = text
            #endif
            didCopy = true
        }
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}

/// Text to type or paste on a server, shown as it will be used.
struct CommandText: View {
    let text: String

    var body: some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            CopyButton(text: text)
        }
    }
}
