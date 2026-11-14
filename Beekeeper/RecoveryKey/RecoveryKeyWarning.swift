import SwiftUI

/// Shown on the Hive's overview until it has a recovery key.
struct RecoveryKeyWarning: View {
    let onSetUp: () -> Void
    /// Offered only for a Hive on this Mac with nothing set up yet.
    var onRestore: (() -> Void)?

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save this Hive's recovery key")
                        .font(.headline)
                    Text(
                        "Without one, this Hive can't be brought back on another Mac with its passwords and SSH keys, "
                            + "and it writes no recovery files."
                    )
                    .foregroundStyle(.secondary)
                }
            }
            Button("Set Up Recovery Key…", action: onSetUp)
            if let onRestore {
                Button("Restore from a Recovery File…", action: onRestore)
            }
        }
    }
}
