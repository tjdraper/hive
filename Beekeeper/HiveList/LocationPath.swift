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
    /// A page with tabs in the toolbar's middle keeps the title on iPad, where removing it takes the tabs too.
    func locationPath(_ parts: [LocationPath.Part], besideTabs: Bool = false) -> some View {
        #if os(macOS)
        toolbar {
            // Without the glass capsule toolbar items get, so it reads as the title it stands in for.
            ToolbarItem(placement: .navigation) {
                LocationPath(parts: parts)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbar(removing: .title)
        #else
        modifier(PadLocationPath(parts: parts, besideTabs: besideTabs))
        #endif
    }
}

#if os(iOS)
extension EnvironmentValues {
    /// How wide the path can be in the detail's toolbar beside the page's own buttons, or nil before
    /// it's known.
    @Entry var locationPathRoom: CGFloat?
}

/// At iPhone width each part of the path is a page of its own, which the Back button returns to, so the
/// page keeps only its title.
private struct PadLocationPath: ViewModifier {
    let parts: [LocationPath.Part]
    let besideTabs: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .compact {
            content
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        if besideTabs {
                            LocationPath(parts: parts)
                                // iPadOS otherwise gives the item only enough room for its first icon.
                                .fixedSize()
                        } else {
                            FittingLocationPath(parts: parts)
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .modifier(InlineTitle(removesTitle: !besideTabs))
        }
    }
}

/// iPadOS shows an inline title beside the path otherwise, repeating its last part.
private struct InlineTitle: ViewModifier {
    let removesTitle: Bool

    func body(content: Content) -> some View {
        if removesTitle {
            content
                .toolbar(removing: .title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The whole path when it fits, and otherwise only its icons with the page's name under them. Too wide
/// for the toolbar, iPadOS moves the page's buttons into a menu and then hides the path altogether.
private struct FittingLocationPath: View {
    let parts: [LocationPath.Part]

    @Environment(\.locationPathRoom) private var room
    @State private var fullWidth: CGFloat = 0

    var body: some View {
        Group {
            if let room, fullWidth > room {
                CompactLocationPath(parts: parts)
                    .frame(width: max(room, 0), alignment: .leading)
            } else {
                LocationPath(parts: parts)
                    .fixedSize()
            }
        }
        .background {
            LocationPath(parts: parts)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { fullWidth = $0 }
        }
    }
}

private struct CompactLocationPath: View {
    let parts: [LocationPath.Part]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        Image(systemName: "chevron.forward")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let action = part.action {
                        Button(part.title, systemImage: part.systemImage, action: action)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: part.systemImage)
                            .accessibilityLabel(part.title)
                    }
                }
            }
            .labelStyle(.iconOnly)
            .font(.subheadline)
            .fixedSize()
            if let page = parts.last {
                Text(page.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
    }
}
#endif
