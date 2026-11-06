import Darwin
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

/// Runs with databases, whose `docker` and dump tools are scripts on this Mac. No `ssh`, and no server.
struct DatabaseDumpRunTests {
    static let password = DumpCommandTests.awkwardPassword
    static let mysqlInContainer = DatabaseSettings(
        kind: .mysql, location: .container(serviceName: "hive-test_mariadb"), user: "site", name: "site"
    )
    static let mysqlOnHost = DatabaseSettings(kind: .mysql, location: .host, user: "site", name: "site")
    static let postgresOnHost = DatabaseSettings(kind: .postgres, location: .host, user: "shop", name: "shop")

    private static func draft(_ settings: DatabaseSettings, password: String? = password) -> BackupDatabaseDraft {
        BackupDatabaseDraft(id: nil, settings: settings, password: password)
    }

    private func manifest(of snapshot: URL) throws -> SnapshotManifest {
        try SnapshotManifest.decoded(from: Data(contentsOf: snapshot.appending(path: SnapshotManifest.fileName)))
    }

    /// The dumps in the job's only snapshot, finished or not.
    private func dumpsLeft(by fixture: BackupRunFixture) throws -> [String] {
        let snapshot = try #require(try fixture.catalog().first)
        return BackupRunFixture.contents(of: fixture.snapshotURL(snapshot).appending(path: SnapshotManifest.databasesFolder))
    }

    @Test("A run dumps a MySQL database in its container into databases/ after the directories, compressed, and lists it in the manifest")
    func mysqlInContainer() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(databases: [Self.draft(Self.mysqlInContainer)])
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.databaseServer.setContainers([
            containerLine(id: "b", swarmService: "hive-test_mysql"),
            containerLine(id: "a", swarmService: "hive-test_mariadb"),
        ])
        fixture.databaseServer.answer(output: RecordedDumpOutput.mysqlDump)

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == nil)
        #expect(run.directories.count == 1)
        #expect(run.databases.map(\.name) == ["site"])
        #expect(run.databases.first?.bytesDumped == Int64(RecordedDumpOutput.mysqlDump.count))
        let snapshot = try #require(try fixture.snapshots().first)
        let dumps = snapshot.appending(path: "databases")
        #expect(BackupRunFixture.contents(of: dumps) == ["site.sql.gz"])
        #expect(try gunzip(dumps.appending(path: "site.sql.gz")) == RecordedDumpOutput.mysqlDump)
        #expect(try manifest(of: snapshot).databases == [SnapshotManifest.Database(name: "site", kind: .mysql, file: "site.sql.gz")])

        let runs = fixture.databaseServer.runs
        #expect(runs.count == 3)
        #expect(runs.first?.hasPrefix("docker ps") == true)
        #expect(runs.dropFirst().first?.hasPrefix("docker exec --interactive \(String(repeating: "a", count: 64)) sh -c ") == true)
        #expect(runs.last == "mariadb-dump --defaults-extra-file=/dev/stdin --single-transaction --routines --events --no-tablespaces site")
    }

    @Test("The password reaches MySQL only through its option file and Postgres only through PGPASSWORD, never a command line")
    func passwordThroughStandardInput() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(databases: [Self.draft(Self.mysqlInContainer), Self.draft(Self.postgresOnHost)])
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.databaseServer.setContainers([containerLine(id: "a", swarmService: "hive-test_mariadb")])
        fixture.databaseServer.answer(output: RecordedDumpOutput.mysqlDump, tools: ["mariadb-dump"])
        fixture.databaseServer.answer(output: RecordedDumpOutput.postgresDump, tools: ["pg_dump"])

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == nil)
        #expect(fixture.databaseServer.runs.count == 4)
        #expect(fixture.databaseServer.runs.allSatisfy { !$0.contains("t3st") })
        #expect(fixture.databaseServer.optionFile == """
        [client]
        user="site"
        password="Hive t3st: \\"double\\" 'single' \\\\back $HOME #hash"

        """)
        #expect(fixture.databaseServer.postgresPassword == Self.password)
    }

    @Test("A Postgres database on the host is dumped as it comes, without docker")
    func postgresOnHost() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(databases: [Self.draft(Self.postgresOnHost)])
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.databaseServer.answer(output: RecordedDumpOutput.postgresDump)

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == nil)
        let snapshot = try #require(try fixture.snapshots().first)
        #expect(try Data(contentsOf: snapshot.appending(path: "databases/shop.dump")) == RecordedDumpOutput.postgresDump)
        #expect(fixture.databaseServer.runs == [
            "pg_dump --format=custom --no-password --host=127.0.0.1 --username=shop --dbname=shop",
        ])
    }

    @Test("A job with only databases makes a snapshot of its dumps")
    func onlyDatabases() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(directories: [], databases: [Self.draft(Self.postgresOnHost)])
        fixture.databaseServer.answer(output: RecordedDumpOutput.postgresDump)

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == nil)
        let snapshot = try #require(try fixture.snapshots().first)
        #expect(BackupRunFixture.contents(of: snapshot) == ["databases", "databases/shop.dump", SnapshotManifest.fileName])
    }

    @Test("mariadb-dump is used where it's found, mysqldump otherwise, and the step fails where neither is")
    func mysqlTools() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(databases: [Self.draft(Self.mysqlOnHost)])
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.databaseServer.answer(output: RecordedDumpOutput.mysqlDump)
        try fixture.databaseServer.remove("mariadb-dump")

        // Act
        let withMysqldump = try await fixture.run()
        try fixture.databaseServer.remove("mysqldump")
        let withNeither = try await fixture.run()

        // Assert
        #expect(withMysqldump.failure == nil)
        #expect(fixture.databaseServer.runs.first?.hasPrefix("mysqldump ") == true)
        #expect(withNeither.failure == .databaseDumpToolMissing)
    }

    @Test("A wrong password fails the step with its reason, leaving no dump and no complete snapshot")
    func wrongPassword() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(databases: [Self.draft(Self.mysqlOnHost)])
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.databaseServer.answer(output: Data(), error: RecordedDumpOutput.mariadbWrongPassword, status: 2)

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == .databaseLoginRefused)
        #expect(run.databases.map(\.failure) == [.databaseLoginRefused])
        #expect(try fixture.snapshots().isEmpty)
        #expect(try dumpsLeft(by: fixture).isEmpty)
    }

    @Test("A dump cut short or empty fails the step and leaves no dump", arguments: [
        (RecordedDumpOutput.mysqlDumpCut, BackupFailure.databaseDumpIncomplete),
        (Data(), BackupFailure.databaseDumpEmpty),
    ])
    func incompleteDump(output: Data, failure: BackupFailure) async throws {
        // Arrange
        let fixture = try await BackupRunFixture(databases: [Self.draft(Self.mysqlOnHost)])
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.databaseServer.answer(output: output)

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == failure)
        #expect(try dumpsLeft(by: fixture).isEmpty)
    }

    @Test("No match, or more than one, for a service name fails the step without running a dump", arguments: [
        ([containerLine(id: "a", swarmService: "hive-test_mariadb_old")], BackupFailure.databaseContainerNotFound),
        (
            [containerLine(id: "a", swarmService: "hive-test_mariadb"), containerLine(id: "b", composeService: "hive-test_mariadb")],
            BackupFailure.databaseContainerNotUnique
        ),
    ])
    func serviceNameMatches(containers: [String], failure: BackupFailure) async throws {
        // Arrange
        let fixture = try await BackupRunFixture(databases: [Self.draft(Self.mysqlInContainer)])
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.databaseServer.setContainers(containers)
        fixture.databaseServer.answer(output: RecordedDumpOutput.mysqlDump)

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == failure)
        #expect(fixture.databaseServer.runs.count == 1)
        #expect(fixture.databaseServer.runs.first?.hasPrefix("docker ps") == true)
    }

    @Test("A database without a stored password fails without running anything")
    func passwordMissing() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(databases: [Self.draft(Self.mysqlOnHost, password: nil)])
        try fixture.write("hello", to: "srv/site/index.html")

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == .databasePasswordMissing)
        #expect(fixture.databaseServer.runs.isEmpty)
    }

    @Test("A picked-up partial loses the dumps a failed run left, including one for a database the job no longer has")
    func leftoverDumpsRemoved() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(databases: [Self.draft(Self.mysqlOnHost), Self.draft(Self.postgresOnHost)])
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.databaseServer.answer(output: RecordedDumpOutput.mysqlDump, tools: ["mariadb-dump"])
        fixture.databaseServer.answer(output: Data(), error: RecordedDumpOutput.postgresWrongPassword, status: 1, tools: ["pg_dump"])
        let failed = try await fixture.run()
        let leftover = try dumpsLeft(by: fixture)
        var draft = fixture.job.draft
        draft.databases.removeFirst()
        _ = try await fixture.api.send(.put, HiveEndpoint.job(fixture.job.id), json: draft)
        fixture.databaseServer.answer(output: RecordedDumpOutput.postgresDump, tools: ["pg_dump"])

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(failed.failure == .databaseLoginRefused)
        #expect(failed.databases.map(\.failure) == [nil, .databaseLoginRefused])
        #expect(leftover == ["site.sql.gz"])
        #expect(run.failure == nil)
        #expect(try fixture.catalog().count == 1)
        let snapshot = try #require(try fixture.snapshots().first)
        #expect(BackupRunFixture.contents(of: snapshot.appending(path: "databases")) == ["shop.dump"])
        #expect(try manifest(of: snapshot).databases.map(\.name) == ["shop"])
    }
}
