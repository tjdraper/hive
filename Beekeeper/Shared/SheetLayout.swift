import SwiftUI

/// One of a sheet's buttons, such as Cancel, Save or a step's Back.
struct SheetButton {
    let title: String
    var isDisabled = false
    let action: () -> Void
}

/// What a sheet says beside its buttons.
enum SheetMessage {
    /// Such as why saving failed.
    case problem(String)
    /// Such as "Restoring…", with a spinner.
    case working(String?)
}

/// A sheet with its buttons where each platform puts them. On the Mac they're in a bar along the bottom,
/// the confirming one at the trailing end with Cancel beside it, and `secondary` and `message` at the
/// leading end. On iPad and iPhone Cancel and the confirming one are in the navigation bar, Cancel at the
/// leading edge and the confirming one at the trailing, with `title` between, and `secondary` and
/// `message` in a bar along the bottom that only shows while there's one of them.
struct SheetLayout<Content: View>: View {
    let title: String
    var cancel: SheetButton?
    var confirm: SheetButton?
    var secondary: SheetButton?
    var message: SheetMessage?
    @ViewBuilder let content: Content

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            content
            Divider()
            HStack {
                leadingItems
                Spacer()
                if let cancel {
                    Button(cancel.title, role: .cancel, action: cancel.action)
                        .keyboardShortcut(.cancelAction)
                        .disabled(cancel.isDisabled)
                }
                if let confirm {
                    Button(confirm.title, action: confirm.action)
                        .keyboardShortcut(.defaultAction)
                        .disabled(confirm.isDisabled)
                }
            }
            .padding()
        }
        #else
        NavigationStack {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if secondary != nil || message != nil {
                        HStack {
                            leadingItems
                            Spacer()
                        }
                        .padding()
                        .background(.bar)
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let cancel {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(cancel.title, role: .cancel, action: cancel.action)
                                .disabled(cancel.isDisabled)
                        }
                    }
                    if let confirm {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(confirm.title, action: confirm.action)
                                .disabled(confirm.isDisabled)
                        }
                    }
                }
        }
        #endif
    }

    @ViewBuilder private var leadingItems: some View {
        if let secondary {
            Button(secondary.title, action: secondary.action)
                .disabled(secondary.isDisabled)
        }
        switch message {
        case .problem(let text):
            Text(text)
                .foregroundStyle(.red)
        case .working(let text):
            ProgressView()
                .controlSize(.small)
            if let text {
                Text(text)
                    .foregroundStyle(.secondary)
            }
        case nil:
            EmptyView()
        }
    }
}
