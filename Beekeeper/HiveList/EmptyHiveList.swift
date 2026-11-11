import SwiftUI

struct EmptyHiveList: View {
    let onPaired: (UUID) -> Void

    @Environment(\.addHive) private var addHive

    var body: some View {
        ContentUnavailableView {
            Label("No Hives", systemImage: "hexagon")
        } description: {
            #if os(macOS)
            Text(
                "If this Mac runs Hive, pair with it here, with no code. Otherwise, add a Hive with a pairing code "
                    + "from a device already paired with it."
            )
            #else
            Text("Add a Hive with a pairing code from a device already paired with it.")
            #endif
        } actions: {
            #if os(macOS)
            PairWithThisMacButton(title: "Pair with This Mac's Hive", onPaired: onPaired)
            #endif
            Button("Add a Hive with a Pairing Code…") { addHive?() }
        }
    }
}
