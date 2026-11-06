import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct ConfirmationRequirementTests {
    private static let connection = ServerConnection(host: "web.example.com", user: "backup")
    private static let newHost = ServerConnection(host: "other.example.com", user: "backup")
    private static let newPort = ServerConnection(host: "web.example.com", port: 2222, user: "backup")
    private static let newUser = ServerConnection(host: "web.example.com", user: "root")

    private static func server(connection: ServerConnection = connection, quotaBytes: Int64?) -> Server {
        Server(id: UUID(), name: "Web", connection: connection, quotaBytes: quotaBytes, confirmedHostKey: nil, sshKeyFingerprint: nil)
    }

    private static func job(
        retention: RetentionTiers = RetentionTiers(dailySnapshots: 14, monthlySnapshots: 12),
        databases: [BackupDatabase] = []
    ) -> BackupJob {
        BackupJob(id: UUID(), serverID: UUID(), name: "Site", directories: [], databases: databases, times: [], retention: retention)
    }

    struct ServerCase: Sendable {
        let oldQuota: Int64?
        let connection: ServerConnection
        let newQuota: Int64?
        let reasons: Set<ConfirmationReason>
    }

    static let serverCases: [ServerCase] = [
        ServerCase(oldQuota: 100, connection: connection, newQuota: 100, reasons: []),
        ServerCase(oldQuota: 100, connection: connection, newQuota: 200, reasons: []),
        ServerCase(oldQuota: 100, connection: connection, newQuota: nil, reasons: []),
        ServerCase(oldQuota: 100, connection: connection, newQuota: 99, reasons: [.quotaLowered]),
        ServerCase(oldQuota: nil, connection: connection, newQuota: 1_000_000, reasons: [.quotaLowered]),
        ServerCase(oldQuota: 100, connection: newHost, newQuota: 100, reasons: [.connectionChanged]),
        ServerCase(oldQuota: 100, connection: newPort, newQuota: 100, reasons: [.connectionChanged]),
        ServerCase(oldQuota: 100, connection: newUser, newQuota: 50, reasons: [.connectionChanged, .quotaLowered]),
    ]

    static let retentionCases: [(RetentionTiers, Set<ConfirmationReason>)] = [
        (RetentionTiers(dailySnapshots: 13, monthlySnapshots: 12), [.retentionLowered]),
        (RetentionTiers(dailySnapshots: 14, monthlySnapshots: 11), [.retentionLowered]),
        (RetentionTiers(dailySnapshots: 30, monthlySnapshots: 0), [.retentionLowered]),
        (RetentionTiers(dailySnapshots: 15, monthlySnapshots: 12), []),
        (RetentionTiers(dailySnapshots: 14, monthlySnapshots: 12), []),
    ]

    @Test("Changing where Hive connects or lowering the quota needs confirmation, and nothing else does", arguments: serverCases)
    func serverReasons(change: ServerCase) {
        // Arrange
        let old = Self.server(quotaBytes: change.oldQuota)
        let new = Self.server(connection: change.connection, quotaBytes: change.newQuota)

        // Act / Assert
        #expect(ConfirmationRequirement.reasons(from: old, to: new) == change.reasons)
    }

    @Test("Lowering either tier needs confirmation, and raising them doesn't", arguments: retentionCases)
    func retentionReasons(new retention: RetentionTiers, reasons: Set<ConfirmationReason>) {
        // Arrange
        let old = Self.job()
        let new = Self.job(retention: retention)

        // Act / Assert
        #expect(ConfirmationRequirement.reasons(from: old, to: new, passwordsEnteredAt: []) == reasons)
    }

    @Test("Replacing a password needs confirmation, while entering one where there was none doesn't")
    func passwordReasons() {
        // Arrange
        let withPassword = BackupDatabase(id: UUID(), settings: ConfigurationSamples.database, hasPassword: true)
        let withoutPassword = BackupDatabase(id: UUID(), settings: ConfigurationSamples.database, hasPassword: false)
        let added = BackupDatabase(id: UUID(), settings: ConfigurationSamples.database, hasPassword: true)
        let old = Self.job(databases: [withPassword, withoutPassword])
        let new = Self.job(databases: [added, withoutPassword, withPassword])

        // Act / Assert
        #expect(ConfirmationRequirement.reasons(from: old, to: new, passwordsEnteredAt: [2]) == [.passwordReplaced])
        #expect(ConfirmationRequirement.reasons(from: old, to: new, passwordsEnteredAt: [0, 1]).isEmpty)
        #expect(ConfirmationRequirement.reasons(from: old, to: new, passwordsEnteredAt: []).isEmpty)
    }

    @Test("Replacing a host key or Hive's SSH key needs confirmation, while a server's first doesn't")
    func keyReasons() {
        // Arrange
        let first = SSHKeyPair().publicKey
        let second = SSHKeyPair().publicKey

        // Act / Assert
        #expect(ConfirmationRequirement.reasons(replacingHostKey: nil, with: first).isEmpty)
        #expect(ConfirmationRequirement.reasons(replacingHostKey: first, with: first).isEmpty)
        #expect(ConfirmationRequirement.reasons(replacingHostKey: first, with: second) == [.hostKeyReplaced])
        #expect(ConfirmationRequirement.reasons(replacingSSHKey: nil).isEmpty)
        #expect(ConfirmationRequirement.reasons(replacingSSHKey: first) == [.sshKeyReplaced])
    }
}
