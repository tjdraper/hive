import HiveKit
import SwiftUI

/// In the Hive's settings: its recovery key, a new one in place of it, and on the Mac a folder to keep
/// another copy of the recovery file in.
struct RecoverySection: View {
    let hive: KnownHive
    let link: HiveLink
    let copies: RecoveryFileCopies

    private enum KeySheet: Identifiable {
        case setUp
        case replacement

        var id: Self {
            self
        }
    }

    @State private var isAskingForNewKey = false
    @State private var keySheet: KeySheet?

    var body: some View {
        Section {
            LabeledContent("Recovery key") {
                HStack(spacing: 12) {
                    Text(keyDescription)
                        .foregroundStyle(.secondary)
                    if let state = copies.hiveState {
                        if state.hasKey {
                            Button("New Recovery Key…") { isAskingForNewKey = true }
                        } else {
                            Button("Set Up…") { keySheet = .setUp }
                        }
                    }
                }
            }
            #if os(macOS)
            RecoveryFolderRow(hiveName: hive.name, copies: copies)
            #endif
        } header: {
            Text("Recovery")
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Make a new recovery key for “\(hive.name)”?", isPresented: $isAskingForNewKey) {
            Button("Make New Key") { keySheet = .replacement }
        } message: {
            Text(
                "Recovery files from then on open only with the new key, and Beekeeper deletes the copies it keeps. "
                    + "Copies already in Mac backups still open with the old key."
            )
        }
        .sheet(item: $keySheet) { sheet in
            RecoveryKeySheet(hiveName: hive.name, link: link, isReplacing: sheet == .replacement) { copies.receive($0) }
        }
        .task { await copies.refresh() }
    }

    private var keyDescription: String {
        guard let state = copies.hiveState else { return "…" }
        guard let saved = state.keySavedAt else { return "Not set up" }
        return "Saved \(saved.formatted(date: .abbreviated, time: .omitted))"
    }

    private var footer: String {
        let opens = "The recovery key opens this Hive's recovery files, which bring it back on another Mac. "
        #if os(macOS)
        return opens + "Beekeeper keeps the latest file on this Mac, and a folder in iCloud Drive keeps another copy off it."
        #else
        return opens + "Beekeeper keeps the latest file on this device."
        #endif
    }
}
