#if DEBUG
import HiveKit
import SwiftUI

/// The addresses for other devices with a few already added, and with none. Choose an iPad in the
/// canvas's device menu to see it as iPad shows it.
private struct AddressOptionsPreview: View {
    @State private var options: [AddressOption]

    init(options: [AddressOption]) {
        _options = State(initialValue: options)
    }

    var body: some View {
        Form {
            AddressOptionsSection(
                options: $options,
                networkAccess: .allAddresses,
                suggestedHosts: [
                    SuggestedHost(host: "karrin.tail0000.ts.net", label: "Tailscale name", address: "100.106.46.52"),
                    SuggestedHost(host: "Karrin.local", label: "Bonjour name", address: nil),
                ],
                hivePort: 4483
            ) {
                HStack {
                    Spacer()
                    Button("Revert") {
                        // Nothing to revert in a preview.
                    }
                    #if os(iOS)
                    .buttonStyle(.bordered)
                    #endif
                    Button("Save") {
                        // Nothing to save in a preview.
                    }
                    #if os(iOS)
                    .buttonStyle(.borderedProminent)
                    #endif
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Addresses") {
    AddressOptionsPreview(options: [
        AddressOption(host: "karrin.tail0000.ts.net"),
        AddressOption(host: "10.0.0.8"),
        AddressOption(host: "hive.example.com", port: 443),
    ])
}

#Preview("No addresses") {
    AddressOptionsPreview(options: [])
}
#endif
