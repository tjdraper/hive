import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct DumpResultReaderTests {
    private func failed(_ status: Int32, _ error: String) -> BackupFailure {
        DumpResultReader.failure(of: ChildProcess.Result(status: status, standardOutput: Data(), standardError: Data(error.utf8)))
    }

    private func finished(_ kind: DatabaseKind, writing dump: Data) -> BackupFailure? {
        var summary = DumpFileSummary()
        summary.record(dump)
        let result = ChildProcess.Result(status: 0, standardOutput: Data(), standardError: Data())
        return DumpResultReader.failure(of: result, kind: kind, dump: summary)
    }

    @Test("A wrong password is told apart for MySQL, MariaDB and Postgres, and an unknown Postgres user reads the same")
    func wrongPassword() {
        #expect(failed(2, RecordedDumpOutput.mysqlWrongPassword) == .databaseLoginRefused)
        #expect(failed(2, RecordedDumpOutput.mariadbWrongPassword) == .databaseLoginRefused)
        #expect(failed(1, RecordedDumpOutput.postgresWrongPassword) == .databaseLoginRefused)
        #expect(failed(1, RecordedDumpOutput.postgresUnknownUser) == .databaseLoginRefused)
    }

    @Test("A missing database, a missing privilege and an unreachable server are told apart")
    func otherFailures() {
        #expect(failed(2, RecordedDumpOutput.mysqlUnknownDatabase) == .databaseMissing)
        #expect(failed(1, RecordedDumpOutput.postgresUnknownDatabase) == .databaseMissing)
        #expect(failed(2, RecordedDumpOutput.mysqlOtherDatabase) == .databaseNotPermitted)
        #expect(failed(2, RecordedDumpOutput.mysqlInsufficientPrivileges) == .databaseNotPermitted)
        #expect(failed(2, RecordedDumpOutput.mysqlUnreachable) == .databaseUnreachable)
        #expect(failed(1, RecordedDumpOutput.postgresUnreachable) == .databaseUnreachable)
    }

    @Test("A missing dump tool, a container gone since it was found, and anything else are their own failures")
    func toolsAndContainers() {
        #expect(failed(127, RecordedDumpOutput.mysqlToolMissing) == .databaseDumpToolMissing)
        #expect(failed(127, RecordedDumpOutput.postgresToolMissing) == .databaseDumpToolMissing)
        #expect(failed(1, RecordedDumpOutput.noSuchContainer) == .databaseContainerNotFound)
        #expect(failed(3, "something unexpected\n") == .databaseDumpFailed)
    }

    @Test("ssh's own failures are read as the connection's")
    func connectionFailures() {
        #expect(failed(255, "ssh: connect to host 127.0.0.1 port 2222: Connection refused\r\n") == .unreachable)
        #expect(failed(255, "Host key verification failed.\r\n") == .hostKeyChanged)
    }

    @Test("A dump that exits cleanly still fails when empty, a MySQL one without its closing line, or a Postgres one not an archive")
    func incompleteDumps() {
        #expect(finished(.mysql, writing: Data()) == .databaseDumpEmpty)
        #expect(finished(.postgres, writing: Data()) == .databaseDumpEmpty)
        #expect(finished(.mysql, writing: RecordedDumpOutput.mysqlDumpCut) == .databaseDumpIncomplete)
        #expect(finished(.postgres, writing: RecordedDumpOutput.mysqlDump) == .databaseDumpIncomplete)
        #expect(finished(.mysql, writing: RecordedDumpOutput.mysqlDump) == nil)
        #expect(finished(.postgres, writing: RecordedDumpOutput.postgresDump) == nil)
    }
}
