import SwiftUI

/// Where the detail sits in the sidebar's tree, as Xcode's jump bar shows it, so a server whose Hive
/// is collapsed still says which Hive it's on. Each part above the last goes there.
struct LocationPath: View {
    struct Part {
        let title: String
        let systemImage: String
        var action: (() -> Void)?
    }

    let parts: [Part]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Image(systemName: "chevron.forward")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let action = part.action {
                    Button(action: action) {
                        Label(part.title, systemImage: part.systemImage)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                } else {
                    Label(part.title, systemImage: part.systemImage)
                        .fontWeight(.semibold)
                }
            }
        }
        .lineLimit(1)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 8)
    }
}

extension View {
    /// Shows `parts` in place of the toolbar's title. The title stays the window's name, for the Window menu.
    func locationPath(_ parts: [LocationPath.Part]) -> some View {
        toolbar {
            // Without the glass capsule toolbar items get, so it reads as the title it stands in for.
            ToolbarItem(placement: .navigation) {
                LocationPath(parts: parts)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        #if os(macOS)
        .toolbar(removing: .title)
        #endif
    }
}
