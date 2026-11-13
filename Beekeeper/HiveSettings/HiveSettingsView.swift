import HiveKit
import SwiftUI

struct HiveSettingsView: View {
    let hive: KnownHive
    let link: HiveLink
    let recovery: RecoveryFileCopies

    @Environment(HiveListStore.self) private var store
    @State private var state: HiveSettingsState?
    @State private var draft: SettingsDraft?
    @State private var isSaving = false
    @State private var failure: String?

    var body: some View {
        Group {
            if let state, let draft = Binding($draft) {
                form(state: state, draft: draft)
            } else if let failure {
                ContentUnavailableView("Couldn't Load the Settings", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func form(state: HiveSettingsState, draft: Binding<SettingsDraft>) -> some View {
        Form {
            BackupDriveSection(link: link)

            Section {
                StackedRow(title: "Name") {
                    TextField("Name", text: draft.name)
                        .stackedField("Name")
                }
            }

            networkSection(state: state, draft: draft)

            Section {
                Toggle("Advertise on the Local Network", isOn: draft.advertisesOnLocalNetwork)
            } footer: {
                Text(advertisingFooter(draft.wrappedValue))
                    .foregroundStyle(.secondary)
            }

            AddressOptionsSection(
                options: draft.addressOptions,
                networkAccess: draft.wrappedValue.settings.networkAccess,
                suggestedHosts: state.suggestedHosts,
                hivePort: state.settings.port
            ) {
                saveControls(state: state, draft: draft.wrappedValue)
            }

            EmailSection(hive: hive, link: link)

            RecoverySection(hive: hive, link: link, copies: recovery)

            SSHKeyRotationSection(hive: hive, link: link)

            IdentitySection(hive: hive, link: link)
        }
        .formStyle(.grouped)
    }

    private func networkSection(state: HiveSettingsState, draft: Binding<SettingsDraft>) -> some View {
        Section {
            Picker("Listen on", selection: draft.access) {
                ForEach(SettingsDraft.Access.allCases) { access in
                    Text(access.title).tag(access)
                }
            }
            if draft.wrappedValue.access == .oneAddress {
                Picker("Address", selection: draft.address) {
                    ForEach(addressChoices(state: state, chosen: draft.wrappedValue.address), id: \.address) { choice in
                        Text(choice.label).tag(choice.address)
                    }
                }
            }
            StackedRow(title: "Port") {
                TextField("Port", value: draft.port, format: .number.grouping(.never))
                    .stackedField("Port")
            }
            LabeledContent("Listening on", value: listeningSummary(state.listeningOn))
        } header: {
            Text("Network")
        } footer: {
            Text(networkFooter(state: state, draft: draft.wrappedValue))
                .foregroundStyle(.secondary)
        }
    }

    /// Saves the name, the network and the addresses for other devices together, since which addresses
    /// work depends on where Hive listens.
    private func saveControls(state: HiveSettingsState, draft: SettingsDraft) -> some View {
        HStack {
            if let failure {
                Text(failure)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button("Revert") {
                self.draft = SettingsDraft(state.settings)
                failure = nil
            }
            .disabled(!isChanged(state) || isSaving)
            Button("Save") { Task { await save(draft) } }
                .keyboardShortcut("s")
                .disabled(!isChanged(state) || isSaving)
        }
    }

    private func isChanged(_ state: HiveSettingsState) -> Bool {
        draft.map { $0.settings != state.settings } ?? false
    }

    private struct AddressChoice {
        let address: String
        let label: String
    }

    /// The Mac's addresses, plus the chosen one when the Mac doesn't have it right now.
    private func addressChoices(state: HiveSettingsState, chosen: String) -> [AddressChoice] {
        var choices = state.interfaces.map { AddressChoice(address: $0.address, label: $0.choiceLabel) }
        if !chosen.isEmpty, !choices.contains(where: { $0.address == chosen }) {
            choices.insert(AddressChoice(address: chosen, label: "\(chosen) (not on the Mac right now)"), at: 0)
        }
        if chosen.isEmpty {
            choices.insert(AddressChoice(address: "", label: "Choose an Address"), at: 0)
        }
        return choices
    }

    private func listeningSummary(_ hosts: [String]) -> String {
        hosts.map { $0 == "::" ? "all addresses" : $0 }.joined(separator: ", ")
    }

    private func networkFooter(state: HiveSettingsState, draft: SettingsDraft) -> String {
        if draft.port != state.settings.port {
            return "Devices connected to the Hive when the port changes follow it. Any that aren't have to pair again."
        }
        switch draft.access {
        case .thisMacOnly:
            return "Only Beekeeper on the Hive's Mac can reach it."
        case .oneAddress where !draft.address.isEmpty && !state.listeningOn.contains(draft.address) && draft.settings == state.settings:
            return "The Mac doesn't have this address right now. Hive starts listening on it when it appears."
        case .oneAddress:
            return "Hive also listens on 127.0.0.1, so Beekeeper on the Hive's Mac keeps working."
        case .allAddresses:
            return "Any device on any network the Mac is on can reach Hive. It still has to be paired to sign in."
        }
    }

    private func advertisingFooter(_ draft: SettingsDraft) -> String {
        guard draft.advertisesOnLocalNetwork else {
            return "Devices reach the Hive only at the addresses below."
        }
        if draft.access == .thisMacOnly {
            return "Hive advertises itself with Bonjour on the local networks it listens on, which is none while it listens on "
                + "this Mac only."
        }
        return "Paired devices on the same local network as the Mac find the Hive there with Bonjour, even when the addresses "
            + "below don't reach it. Never over Tailscale."
    }

    private func load() async {
        do {
            let loaded: HiveSettingsState = try await link.perform { try await $0.get(HiveEndpoint.settings) }
            state = loaded
            draft = SettingsDraft(loaded.settings)
            failure = nil
        } catch {
            failure = HiveLink.message(for: error)
        }
    }

    private func save(_ draft: SettingsDraft) async {
        isSaving = true
        defer { isSaving = false }
        let new = draft.settings
        do {
            let saved: HiveSettingsState = try await link.perform { try await $0.put(HiveEndpoint.settings, body: new) }
            state = saved
            self.draft = SettingsDraft(saved.settings)
            failure = nil
            store.rename(hive.id, to: saved.settings.name)
            store.follow(hive.id, to: saved.settings.addresses)
        } catch let refused as HiveRequestError {
            failure = (try? JSONDecoder().decode(SettingsRefusal.self, from: refused.body)).map { Self.message(for: $0.problem) }
                ?? HiveLink.message(for: refused)
        } catch {
            failure = HiveLink.message(for: error)
        }
    }

    private static func message(for problem: SettingsProblem) -> String {
        switch problem {
        case .invalidName: "Enter a name of up to 100 characters."
        case .invalidPort: "Choose a port from 1024 to 65535."
        case .invalidAddress: "Choose an address another device could reach the Mac at."
        case .portUnavailable: "Something else on the Hive's Mac is using that port."
        case .invalidAddressOption: "Each address for other devices has to be a name or IP address they could reach, listed once."
        case .tooManyAddressOptions: "Use at most \(PairingCode.largestAddressCount) addresses for other devices."
        }
    }
}

/// The settings as they're being edited, with the address kept while another choice is picked.
struct SettingsDraft: Equatable {
    enum Access: CaseIterable, Identifiable {
        case thisMacOnly
        case oneAddress
        case allAddresses

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .thisMacOnly: "This Mac Only"
            case .oneAddress: "This Mac and One Address"
            case .allAddresses: "All Addresses"
            }
        }
    }

    var name: String
    var access: Access
    var address: String
    var port: Int
    var addressOptions: [AddressOption]
    var advertisesOnLocalNetwork: Bool

    init(_ settings: HiveSettings) {
        name = settings.name
        port = settings.port
        addressOptions = settings.addressOptions
        advertisesOnLocalNetwork = settings.advertisesOnLocalNetwork
        switch settings.networkAccess {
        case .thisMacOnly:
            access = .thisMacOnly
            address = ""
        case .address(let chosen):
            access = .oneAddress
            address = chosen
        case .allAddresses:
            access = .allAddresses
            address = ""
        }
    }

    var settings: HiveSettings {
        let networkAccess: NetworkAccess = switch access {
        case .thisMacOnly: .thisMacOnly
        case .oneAddress: .address(address)
        case .allAddresses: .allAddresses
        }
        return HiveSettings(
            name: name,
            networkAccess: networkAccess,
            port: port,
            addressOptions: addressOptions,
            advertisesOnLocalNetwork: advertisesOnLocalNetwork
        )
    }
}

extension NetworkInterfaceAddress {
    /// Such as "100.101.102.103 — Tailscale (studio.tail0000.ts.net)", with the BSD name when macOS
    /// gives the interface no name of its own.
    var choiceLabel: String {
        let what = displayName.map { "\($0), \(interface)" } ?? interface
        let name = hostName.map { " (\($0))" } ?? ""
        return "\(address) — \(what)\(name)"
    }
}

extension NetworkAccess {
    var summary: String {
        switch self {
        case .thisMacOnly: "this Mac only"
        case .address(let address): "this Mac and \(address)"
        case .allAddresses: "all addresses"
        }
    }
}
