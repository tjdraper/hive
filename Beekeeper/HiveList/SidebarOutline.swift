import SwiftUI

/// A sidebar row with rows under it that can be hidden. On the Mac it's the native outline. On iPad
/// it's plain rows, the ones under it indented, with the row drawing its own arrow
/// (`SidebarDisclosureButton`). iPadOS doesn't keep a selected row highlighted while it's a
/// `DisclosureGroup`'s label: the highlight goes when a sheet closes, and a selection made in code,
/// such as the first Hive at launch, never shows.
struct SidebarOutline<Row: View, Children: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder let row: () -> Row
    @ViewBuilder let children: () -> Children

    var body: some View {
        #if os(macOS)
        DisclosureGroup(isExpanded: $isExpanded, content: children, label: row)
        #else
        row()
        if isExpanded {
            children()
                .padding(.leading, 20)
        }
        #endif
    }
}

/// The arrow at the end of an iPad sidebar row that has rows under it. The Mac's outline draws its own.
struct SidebarDisclosureButton: View {
    @Binding var isExpanded: Bool?

    var body: some View {
        #if os(iOS)
        if let expanded = isExpanded {
            Button(expanded ? "Collapse" : "Expand", systemImage: "chevron.down") {
                withAnimation { isExpanded = !expanded }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            // As the native arrow is, so it turns white with the rest of a selected row.
            .foregroundStyle(.primary)
            .fontWeight(.semibold)
            .rotationEffect(.degrees(expanded ? 0 : -90))
        }
        #endif
    }
}
