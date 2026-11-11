import Foundation
import HiveKit
import os

enum SSHKeyRotationError: Error, Equatable {
    case alreadyRunning
}

/// Gives every server a new SSH key of Hive's (§14), one action for when the old Mac may have been
/// stolen. For each server Hive adds the new key beside the old one using the old one, checks the new
/// one works, keeps it, then removes exactly the old key's lines using the new one. A server where any
/// step before keeping it fails keeps its old key, which Hive goes on using.
///
/// It holds the job queue while it runs, so no backup connects in the middle with a key about to go.
/// Only the latest rotation's results are kept, until Hive stops.
actor SSHKeyRotationWorkflow {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "SSHKeys")

    private let database: HiveDatabase
    private let sealer: SecretSealer
    private let targets: SSHTargetLoader
    private let ssh: any SSHRunning
    private let runs: BackupRunCoordinator
    private let settings: HiveSettingsStore
    private let now: @Sendable () -> Date
    private var current = SSHKeyRotationState(startedAt: nil, finishedAt: nil, results: [])
    private var running: Task<Void, Never>?

    init(
        database: HiveDatabase,
        sealer: SecretSealer,
        ssh: any SSHRunning,
        runs: BackupRunCoordinator,
        settings: HiveSettingsStore,
        now: @escaping @Sendable () -> Date
    ) {
        self.database = database
        self.sealer = sealer
        targets = SSHTargetLoader(database: database, sealer: sealer)
        self.ssh = ssh
        self.runs = runs
        self.settings = settings
        self.now = now
    }

    func state() -> SSHKeyRotationState {
        current
    }

    /// Throws `ConfirmationError.required` unless confirmed, and `SSHKeyRotationError.alreadyRunning`
    /// while one runs. Returns at once, with the results to come.
    func start(isConfirmed: Bool, by deviceID: UUID) throws -> SSHKeyRotationState {
        try ConfirmationRequirement.check([.sshKeysRotated], isConfirmed: isConfirmed)
        guard running == nil else { throw SSHKeyRotationError.alreadyRunning }
        current = SSHKeyRotationState(startedAt: now(), finishedAt: nil, results: [])
        running = Task {
            await runs.whileHeld { await self.rotateEveryServer(by: deviceID) }
            finish()
        }
        Self.logger.notice("Started rotating SSH keys")
        return current
    }

    /// Returns once the rotation going now, if any, has finished.
    func waitUntilFinished() async {
        await running?.value
    }

    private func finish() {
        current = SSHKeyRotationState(startedAt: current.startedAt, finishedAt: now(), results: current.results)
        running = nil
    }

    private func record(_ result: SSHKeyRotationResult) {
        current = SSHKeyRotationState(startedAt: current.startedAt, finishedAt: nil, results: current.results + [result])
    }

    private func rotateEveryServer(by deviceID: UUID) async {
        let clock = ContinuousClock.now
        let servers: [Server]
        let comment: String
        do {
            servers = try ServerStore(database: database).all()
            comment = "Hive \(try settings.settings().name)"
        } catch {
            Self.logger.error("Couldn't read the servers to rotate: \(String(describing: type(of: error)), privacy: .public)")
            return
        }

        // Each server's own steps run in turn, and servers alongside each other, so one that doesn't
        // answer holds up only itself.
        await withTaskGroup(of: SSHKeyRotationResult.self) { group in
            for server in servers {
                group.addTask {
                    let rotation = ServerKeyRotation(
                        targets: self.targets,
                        ssh: self.ssh,
                        keys: ServerSSHKeyStore(database: self.database),
                        sealer: self.sealer,
                        comment: comment,
                        deviceID: deviceID,
                        now: self.now
                    )
                    return SSHKeyRotationResult(serverID: server.id, serverName: server.name, outcome: await rotation.rotate(server.id))
                }
            }
            for await result in group {
                record(result)
            }
        }

        let outcomes = current.results.map(\.outcome)
        let rotated = outcomes.count(where: { if case .rotated = $0 { true } else { false } })
        let oldKeyLeft = outcomes.count(where: { if case .oldKeyLeft = $0 { true } else { false } })
        let failed = outcomes.count(where: { if case .failed = $0 { true } else { false } })
        let seconds = (ContinuousClock.now - clock).roundedSeconds
        Self.logger.notice("""
        Rotated SSH keys: \(rotated, privacy: .public) rotated, \(oldKeyLeft, privacy: .public) with the old key left, \
        \(failed, privacy: .public) failed, of \(servers.count, privacy: .public) servers, in \(seconds, privacy: .public)s
        """)
    }
}

/// One server's rotation, each step over its own connection.
private struct ServerKeyRotation {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "SSHKeys")

    let targets: SSHTargetLoader
    let ssh: any SSHRunning
    let keys: ServerSSHKeyStore
    let sealer: SecretSealer
    let comment: String
    let deviceID: UUID
    let now: @Sendable () -> Date

    func rotate(_ serverID: UUID) async -> SSHKeyRotationOutcome {
        do {
            return try await rotateOrThrow(serverID)
        } catch {
            Self.logger.error("Couldn't rotate a server's SSH key: \(String(describing: type(of: error)), privacy: .public)")
            return .failed(.connection(.failed))
        }
    }

    private func rotateOrThrow(_ serverID: UUID) async throws -> SSHKeyRotationOutcome {
        guard case .ready(let old) = try targets.target(forServer: serverID) else { return .notSetUp }

        let read = try await ssh.run(AuthorizedKeysScript.read, on: old)
        if let failure = Self.connectionFailure(in: read) { return .failed(.connection(failure)) }
        let oldEntries = AuthorizedKeysFile.entries(for: old.key.publicKey, in: read.standardOutput)
        guard read.status == 0, let first = oldEntries.first else { return .failed(.oldKeyNotFound) }

        let newKey = SSHKeyPair()
        let newLine = AuthorizedKeysFile.line(like: first, for: newKey.publicKey, comment: comment)
        let added = try await ssh.run(AuthorizedKeysScript.add(newLine), on: old)
        if let failure = Self.connectionFailure(in: added) { return .failed(.connection(failure)) }
        guard added.status == 0 else { return .failed(.couldNotAddNewKey) }

        let new = SSHTarget(serverID: serverID, connection: old.connection, hostKey: old.hostKey, key: newKey)
        let check = try await ssh.run(ConnectionTestWorkflow.harmlessCommand, on: new)
        if let failure = SSHFailureReader.failure(in: check) {
            // The new key is no use to anyone, so its line goes again, with the old key that still works.
            _ = try? await ssh.run(AuthorizedKeysScript.remove([newLine], keeping: first.line), on: old)
            return .failed(.newKeyRefused(failure))
        }

        // Kept before the old key goes, so a server never accepts only a key Hive doesn't have.
        guard try keys.rotateKey(forServer: serverID, from: old, to: SealedSSHKey(newKey, sealer: sealer), by: deviceID, at: now()) else {
            _ = try? await ssh.run(AuthorizedKeysScript.remove([newLine], keeping: first.line), on: old)
            return .failed(.serverChanged)
        }

        let fingerprint = newKey.publicKey.fingerprint
        let removed = try? await ssh.run(AuthorizedKeysScript.remove(oldEntries.map(\.line), keeping: newLine), on: new)
        return removed?.status == 0 ? .rotated(fingerprint: fingerprint) : .oldKeyLeft(fingerprint: fingerprint)
    }

    /// Nil when `ssh` connected, whatever the command then did.
    private static func connectionFailure(in result: ChildProcess.Result) -> ConnectionFailure? {
        guard result.status == SSHFailureReader.sshErrorStatus else { return nil }
        return SSHFailureReader.recognizedFailure(in: result.standardError) ?? .failed
    }
}
