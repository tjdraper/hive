import SwiftUI

/// Whether the Hive emails before a device's iPhone or iPad build expires, in the Hive's settings. It
/// saves as soon as it's changed, since it's apart from the settings above that wait for Save.
struct BuildExpiryWarningsSection: View {
    let isOn: Bool
    /// Returns why it couldn't be saved.
    let save: (Bool) async -> String?

    @State private var pending: Bool?
    @State private var failure: String?

    var body: some View {
        Section {
            Toggle("Email Before a Build Expires", isOn: Binding(get: { pending ?? isOn }, set: { change(to: $0) }))
                .disabled(pending != nil)
        } header: {
            Text("Build Expiry Warnings")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Hive emails 14 days and 3 days before Beekeeper stops opening on a paired iPhone or iPad. "
                        + "With several Hives, turn this on in only one, so each warning comes once."
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
