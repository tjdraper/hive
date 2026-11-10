import HiveKit
import SwiftUI

/// A backup found the server showing a host key other than the confirmed one.
struct HostKeyChange: Equatable {
    /// The newest complete snapshot of any of the server's jobs.
    let lastBackup: Date?
}

/// Scanning a server's host key and confirming it once the person has checked the fingerprint. Hive
/// connects to a server only with a confirmed key, so nothing between them can stand in for it.
/// Replacing a confirmed key asks for Touch ID or the password.
struct HostKeyCheck: View {
    let link: HiveLink
    let servers: ServerList
    let server: Server
    var scansOnAppear = false
    var change: HostKeyChange?

    private enum Scan {
        case scanning
        case found(HostKeyFingerprint)
        case failed(String)
    }

    @State private var scan: Scan?
    @State private var isConfirming = false
    @State private var failure: String?
    /// The new key was confirmed here, so the change the last backup found is dealt with.
    @State private var replacedKey = false

    var body: some View {
        Section("Host Key") {
            if let confirmed = server.confirmedHostKey {
                LabeledContent("Confirmed \(confirmed.typeName) key") {
                    FingerprintText(fingerprint: confirmed.fingerprint)
                }
                if let change, !replacedKey {
                    changed(confirmed, change: change)
                } else if replacedKey {
                    Text("Confirmed. The server's next backup connects with this key.")
                        .foregroundStyle(.secondary)
                }
            } else {
                scanRows(replacing: nil)
            }
        }
        .task(id: change) {
            if change != nil || (scansOnAppear && server.confirmedHostKey == nil) { await scanNow() }
        }
    }

    @ViewBuilder private func changed(_ confirmed: HostKeyFingerprint, change: HostKeyChange) -> some View {
        Label(
            "The last backup found the server showing a different host key, so Hive didn't connect. The server may have "
                + "been reinstalled, or something else may be answering at its address.",
            systemImage: "exclamationmark.shield.fill"
        )
        .foregroundStyle(.orange)
        LabeledContent("Last successful backup") {
            if let lastBackup = change.lastBackup {
                Text(lastBackup.formatted(date: .abbreviated, time: .shortened))
            } else {
                Text("None")
            }
        }
        scanRows(replacing: confirmed)
    }

    /// Scanning, and confirming what the scan found. `replacing` is the confirmed key, when there is one.
    @ViewBuilder private func scanRows(replacing confirmed: HostKeyFingerprint?) -> some View {
        switch scan {
        case nil:
            HStack {
                Text(confirmed == nil ? "Not confirmed yet. Hive won't connect until it is." : "Scan to see the key the server shows now.")
                Spacer()
                Button("Scan Host Key") { Task { await scanNow() } }
            }
        case .scanning:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Asking \(server.connection.host) for its host key…")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Scan Again") { Task { await scanNow() } }
            }
        case .found(let key) where key == confirmed:
            HStack {
                Text("The server shows its confirmed key again, so its next backup connects.")
                Spacer()
                Button("Scan Again") { Task { await scanNow() } }
            }
        case .found(let key):
            found(key, replacing: confirmed)
        }
    }

    @ViewBuilder private func found(_ key: HostKeyFingerprint, replacing confirmed: HostKeyFingerprint?) -> some View {
        Text(
            "\(server.connection.host) showed this \(confirmed == nil ? "" : "new ")\(key.typeName) key. Before confirming it, "
                + "check that it matches the server's own, so Hive never trusts a machine standing in for the server."
        )
        FingerprintText(fingerprint: key.fingerprint)
            .font(.title3.monospaced())
        Text("On the server, this shows its fingerprint:")
            .foregroundStyle(.secondary)
        CommandText(text: "ssh-keygen -lf /etc/ssh/\(key.hostKeyFile)")
        if let failure {
            Text(failure)
                .foregroundStyle(.red)
        }
        HStack {
            Button("Scan Again") { Task { await scanNow() } }
            Spacer()
            Button(confirmed == nil ? "It Matches, Confirm" : "It Matches, Confirm New Key") {
                Task { await confirm(key, replacing: confirmed != nil) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConfirming)
        }
    }

    private func scanNow() async {
        scan = .scanning
        failure = nil
        do {
            let result: HostKeyScanResult = try await link.perform { try await $0.post(HiveEndpoint.hostKeyScan(onServer: server.id)) }
            switch result {
            case .found(let key): scan = .found(key)
            case .failed(let reason): scan = .failed(reason.message(for: server))
            }
        } catch {
            scan = .failed(HiveLink.message(for: error))
        }
    }

    private func confirm(_ key: HostKeyFingerprint, replacing: Bool) async {
        isConfirming = true
        defer { isConfirming = false }
        do {
            let confirmed: Server = try await link.confirmed(
                "PUT",
                HiveEndpoint.hostKey(onServer: server.id),
                body: HostKeyConfirmation(fingerprint: key.fingerprint),
                reason: replacing ? "confirm a new host key for “\(server.name)”" : nil
            )
            servers.update(confirmed)
            scan = nil
            replacedKey = replacing
        } catch ConfirmationKeyError.cancelled {
            // Left unconfirmed, as the person chose.
        } catch let refused as HiveRequestError where refused.status == 409 {
            let reason = try? JSONDecoder().decode(HostKeyConfirmationRefusal.self, from: refused.body).reason
            failure = switch reason {
            case .fingerprintMismatch: "The server's key changed since the scan. Scan again and check the new one."
            case .noScan, nil: "The scan is too old, or the server's connection changed since. Scan again."
            }
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}

private struct FingerprintText: View {
    let fingerprint: String

    var body: some View {
        Text(fingerprint)
            .monospaced()
            .textSelection(.enabled)
    }
}

extension HostKeyFingerprint {
    /// As `ssh-keygen -l` names the type.
    var typeName: String {
        switch keyType {
        case "ssh-ed25519": "ED25519"
        case "ssh-rsa": "RSA"
        default: keyType.hasPrefix("ecdsa-") ? "ECDSA" : keyType
        }
    }

    /// Where OpenSSH keeps a server's public host key of this type, under `/etc/ssh`.
    var hostKeyFile: String {
        "ssh_host_\(typeName.lowercased())_key.pub"
    }
}
