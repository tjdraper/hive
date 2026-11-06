import SwiftUI

struct EmptyHiveList: View {
    let onPaired: (UUID) -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Hives", systemImage: "hexagon")
        } description: {
            #if os(macOS)
            Text("If this Mac runs Hive, pair with it here. No code is needed.")
            #else
            Text("Pairing with a Hive from this device comes later.")
            #endif
        } actions: {
            #if os(macOS)
            PairWithThisMacButton(title: "Pair with This Mac's Hive", onPaired: onPaired)
            #endif
        }
    }
}
