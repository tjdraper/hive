import SwiftUI

/// Whether the Hive reads its own Mac's figures, in the Hive's settings. It saves as soon as it's
/// changed, since it's apart from the settings above that wait for Save.
struct HiveMacMetricsSection: View {
    let isOn: Bool
    /// Returns why it couldn't be saved.
    let save: (Bool) async -> String?

    @State private var pending: Bool?
    @State private var failure: String?

    var body: some View {
        Section {
            Toggle("Read the Hive Mac's Metrics", isOn: Binding(get: { pending ?? isOn }, set: { change(to: $0) }))
                .disabled(pending != nil)
        } header: {
            Text("Hive Mac Metrics")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Hive reads its Mac's CPU, memory, disks, network and processes every 10 seconds, as Scout reads a "
                        + "server's, and shows them on the dashboard. Turning it off keeps those already read, "
                        + "which show again when it's turned back on."
                )
                .foregroundStyle(.secondary)
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func change(to new: Bool) {
        pending = new
        Task {
            failure = await save(new)
            pending = nil
        }
    }
}
