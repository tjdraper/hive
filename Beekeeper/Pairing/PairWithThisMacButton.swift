#if os(macOS)
import HiveKit
import SwiftUI

/// Pairs with this Mac's Hive over XPC, with no code to enter.
struct PairWithThisMacButton: View {
    let title: String
    let onPaired: (UUID) -> Void

    @Environment(HiveListStore.self) private var store
    @State private var isPairing = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 8) {
            Button(title) {
                Task { await pair() }
            }
            .disabled(isPairing)

            if isPairing {
                ProgressView()
                    .controlSize(.small)
            }
            if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
    }

    private func pair() async {
        isPairing = true
        failure = nil
        defer { isPairing = false }
        do {
            onPaired(try await store.pairWithThisMac())
        } catch {
            failure = Self.message(for: error)
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case LocalPairingError.unreachable:
            "Couldn't reach this Mac's Hive. Check that it's turned on in Hive."
        case LocalPairingError.refused(.notBeekeeper):
            "This Mac's Hive only pairs with Beekeeper signed by the same developer."
        case LocalPairingError.refused(let refusal):
            "This Mac's Hive turned down the pairing (\(refusal.rawValue))."
        case DeviceKeyError.secureEnclaveUnavailable:
            "This Mac has no Secure Enclave for Beekeeper's key."
        default:
            HiveLink.message(for: error)
        }
    }
}
#endif
