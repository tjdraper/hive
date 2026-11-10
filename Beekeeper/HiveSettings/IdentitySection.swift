import HiveKit
import SwiftUI

/// Giving the Hive a new identity key (§5), such as when its Mac may have been compromised. Every device
/// pinned the old key, so each is unpaired. Beekeeper on the Hive's Mac pairs again by itself once Hive
/// has restarted.
struct IdentitySection: View {
    let hive: KnownHive
    let link: HiveLink

    @Environment(HiveListStore.self) private var store
    @State private var isAsking = false
    @State private var isRegenerating = false
    @State private var failure: String?

    var body: some View {
        Section {
            HStack {
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Regenerate Identity…", role: .destructive) { isAsking = true }
                    .disabled(isRegenerating)
            }
        } header: {
            Text("Identity")
        } footer: {
            Text(
                "Every device checks the Hive by its identity key. A new one unpairs every device, this one included. "
                    + (hive.isOnThisMac
                        ? "Beekeeper on this Mac pairs again by itself, and other devices pair again through it."
                        : "Pair again through Beekeeper on the Hive's Mac.")
            )
            .foregroundStyle(.secondary)
        }
        .confirmationDialog("Give “\(hive.name)” a new identity?", isPresented: $isAsking) {
            Button("Regenerate Identity", role: .destructive) { Task { await regenerate() } }
        } message: {
            Text(
                "Every device is unpaired and has to pair again. Hive restarts, stopping any backup that's running, "
                    + "which runs again once it's back."
            )
        }
    }

    private func regenerate() async {
        isRegenerating = true
        defer { isRegenerating = false }
        do {
            let reason = "give “\(hive.name)” a new identity, unpairing every device"
            try await link.confirmed("POST", HiveEndpoint.identityRegeneration, reason: reason)
        } catch ConfirmationKeyError.cancelled {
            return
        } catch {
            failure = HiveLink.message(for: error)
            return
        }
        #if os(macOS)
        if hive.isOnThisMac {
            store.pairAgainAfterNewIdentity(hive.id)
            return
        }
        #endif
        link.forgetCredential()
    }
}
