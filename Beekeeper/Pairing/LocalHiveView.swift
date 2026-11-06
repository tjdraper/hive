#if os(macOS)
import SwiftUI

struct LocalHiveView: View {
    @State private var store = LocalHiveStore()

    var body: some View {
        VStack(spacing: 16) {
            Button("Pair with This Mac's Hive") {
                Task { await store.pairAndSignIn() }
            }
            .disabled(isBusy)

            Text(statusLine)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding()
    }

    private var isBusy: Bool {
        store.state == .pairing || store.state == .signingIn
    }

    private var statusLine: String {
        switch store.state {
        case .notPaired: "Not paired"
        case .pairing: "Pairing…"
        case .signingIn: "Signing in…"
        case .signedIn(let hiveID): "Signed in to this Mac's Hive (\(hiveID.uuidString.prefix(8)))"
        case .failed(let message): message
        }
    }
}
#endif
