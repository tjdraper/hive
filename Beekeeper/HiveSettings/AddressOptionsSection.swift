import HiveKit
import SwiftUI

/// Where other devices reach the Hive, in the order they try them. Pairing codes carry these, and paired
/// devices follow changes to them and to the port. Saved with the network settings they depend on, by
/// `controls` at its foot.
struct AddressOptionsSection<Controls: View>: View {
    @Binding var options: [AddressOption]
    /// Where Hive will listen, as chosen, saved or not.
    let networkAccess: NetworkAccess
    let suggestedHosts: [SuggestedHost]
    let hivePort: Int
    @ViewBuilder let controls: () -> Controls

    @State private var isAddingOther = false

    var body: some View {
        Section {
            if options.isEmpty {
                Text("None yet. Other devices can't pair until there's one.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                row(option, at: index)
            }
            HStack {
                Menu("Add Address", systemImage: "plus") {
                    ForEach(suggestions, id: \.host) { suggestion in
                        Button {
                            options.append(AddressOption(host: suggestion.host))
                        } label: {
                            Text(suggestion.host)
                            Text(suggestion.label)
                        }
                    }
                    if !suggestions.isEmpty { Divider() }
                    Button("Other Address…") { isAddingOther = true }
                }
                .fixedSize()
                .disabled(options.count >= PairingCode.largestAddressCount)
                Spacer()
            }
        } header: {
            Text("Addresses for Other Devices")
        } footer: {
            VStack(alignment: .leading, spacing: 12) {
                Text(explanation)
                    .foregroundStyle(.secondary)
                controls()
            }
        }
        .sheet(isPresented: $isAddingOther) {
            OtherAddressSheet(hivePort: hivePort) { options.append($0) }
        }
    }

    private func row(_ option: AddressOption, at index: Int) -> some View {
        HStack {
            Text(option.host)
                .textSelection(.enabled)
            Spacer()
            Text(option.port.map { "Port \($0.formatted(.number.grouping(.never)))" } ?? "Hive's port")
                .foregroundStyle(.secondary)
            Button("Move Up", systemImage: "chevron.up") { options.swapAt(index, index - 1) }
                .disabled(index == 0)
            Button("Move Down", systemImage: "chevron.down") { options.swapAt(index, index + 1) }
                .disabled(index == options.count - 1)
            Button("Remove", systemImage: "trash") { options.remove(at: index) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    /// The hosts Hive found where it will listen that aren't on the list yet.
    private var suggestions: [SuggestedHost] {
        suggestedHosts.filter { suggestion in
            suggestion.isReachable(through: networkAccess) && !options.contains { $0.host == suggestion.host }
        }
    }

    private var explanation: String {
        let order = "Devices try these in order. Each uses the Hive's port unless it has its own, for a port forward or a tunnel."
        if networkAccess == .thisMacOnly {
            return "Hive listens on this Mac only, so other devices can't reach it at any of these. Choose where it listens in Network. "
                + order
        }
        return order
    }
}

/// An address Hive didn't suggest, such as a public hostname, with the port a port forward or tunnel uses.
private struct OtherAddressSheet: View {
    let hivePort: Int
    let onAdd: (AddressOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var usesOwnPort = false
    @State private var port: Int?

    var body: some View {
        SheetLayout(
            title: "Add an Address",
            cancel: SheetButton(title: "Cancel") { dismiss() },
            confirm: SheetButton(
                title: "Add",
                isDisabled: host.trimmingCharacters(in: .whitespaces).isEmpty || (usesOwnPort && port == nil)
            ) {
                onAdd(AddressOption(host: host.trimmingCharacters(in: .whitespaces), port: usesOwnPort ? port : nil))
                dismiss()
            }
        ) {
            Form {
                StackedRow(title: "Name or IP Address") {
                    TextField("Name or IP Address", text: $host, prompt: Text("hive.example.com"))
                        .autocorrectionDisabled()
                        .stackedField("Name or IP Address")
                }
                Toggle("Reached on another port", isOn: $usesOwnPort)
                if usesOwnPort {
                    StackedRow(title: "Port") {
                        TextField("Port", value: $port, format: .number.grouping(.never), prompt: Text(String(hivePort)))
                            .stackedField("Port")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .macSheetSize(width: 420, height: 320)
    }
}
