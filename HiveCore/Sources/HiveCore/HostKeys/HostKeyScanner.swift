import Foundation
import HiveKit

enum HostKeyScanOutcome: Equatable, Sendable {
    case found(OpenSSHPublicKey)
    case failed(ConnectionFailure)
}

/// Asks a server for its host key. Tests stand in for it, since they never reach a server.
protocol HostKeyScanning: Sendable {
    func scan(_ connection: ServerConnection) async throws -> HostKeyScanOutcome
}

/// Scans with `ssh-keyscan`, which signs in to nothing and reads no config. Anyone between Hive and the
/// server could answer in its place, which is why a person checks the fingerprint before it's recorded.
struct HostKeyScanner: HostKeyScanning {
    static let timeoutSeconds = 10

    var tools = SSHTools()

    func scan(_ connection: ServerConnection) async throws -> HostKeyScanOutcome {
        let result = try await ChildProcess(
            executableURL: tools.keyscan,
            arguments: [
                "-T", String(Self.timeoutSeconds),
                "-p", String(connection.port),
                "-t", "ed25519,ecdsa,rsa",
                "--", connection.host,
            ],
            environment: SSHTools.environment()
        ).run()
        return HostKeyScanParser.outcome(from: String(bytes: result.standardOutput, encoding: .utf8) ?? "")
    }
}

/// Reads what `ssh-keyscan` printed: a `<host> <type> <key>` line for each key it was given.
enum HostKeyScanParser {
    static func outcome(from output: String) -> HostKeyScanOutcome {
        let keys = output.split(whereSeparator: \.isNewline).compactMap { line -> OpenSSHPublicKey? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard !line.hasPrefix("#"), fields.count >= 3 else { return nil }
            return OpenSSHPublicKey(line: fields[1...].joined(separator: " "))
        }
        // ssh-keyscan says little about why it found nothing, only "Broken pipe" for a refused
        // connection, so finding nothing at all is read as the server not answering.
        guard !keys.isEmpty else { return .failed(.unreachable) }
        for type in OpenSSHPublicKey.hostKeyTypes {
            if let key = keys.first(where: { $0.keyType == type }) { return .found(key) }
        }
        return .failed(.failed)
    }
}
