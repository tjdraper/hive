import SwiftUI

extension View {
    /// Asks before removing `removing` from Beekeeper, saying whether the Hive will still list this device.
    func hiveRemoval(_ removing: Binding<KnownHive?>, onRemove: @escaping (KnownHive) async -> Void) -> some View {
        modifier(HiveRemovalDialog(removing: removing, onRemove: onRemove))
    }
}

private struct HiveRemovalDialog: ViewModifier {
    @Binding var removing: KnownHive?
    let onRemove: (KnownHive) async -> Void

    @Environment(HiveListStore.self) private var store

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Remove “\(removing?.name ?? "")” from Beekeeper?",
                isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } },
                presenting: removing
            ) { hive in
                Button("Remove", role: .destructive) { Task { await onRemove(hive) } }
            } message: { hive in
                Text(message(for: hive))
            }
    }

    private func message(for hive: KnownHive) -> String {
        let again = hive.isOnThisMac
            ? "This Mac can pair with it again with no code."
            : "Pairing again takes a code from a device that's paired with it."
        if store.link(for: hive.id)?.status == .connected {
            return "Beekeeper revokes this device on the Hive, so it leaves the Hive's device list, and forgets its key. " + again
        }
        return "Beekeeper can't reach the Hive, so this device stays in the Hive's device list until it's revoked from another "
            + "device. Beekeeper forgets its key. " + again
    }
}
