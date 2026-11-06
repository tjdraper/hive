import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct DumpCommandTests {
    /// A space, both quotes, a backslash, `$` and `#`, as in the test server's databases.
    static let awkwardPassword = #"Hive t3st: "double" 'single' \back $HOME #hash"#
    static let containerID = String(repeating: "c", count: 64)

    static let everyDatabase: [DatabaseSettings] = DatabaseKind.allCases.flatMap { kind in
        [DatabaseLocation.host, .container(serviceName: "site_db")].map { location in
            DatabaseSettings(kind: kind, location: location, user: "site", name: "site")
        }
    }

    @Test("No command built for any database kind or location contains the password, and the dump's input does", arguments: everyDatabase)
    func passwordNeverInCommands(settings: DatabaseSettings) {
        // Arrange
        let containerID: String? = settings.location == .host ? nil : Self.containerID

        // Act
        let commands = [DumpCommand.containerList(), DumpCommand.dump(settings, inContainer: containerID)]
        let input = String(bytes: DumpCommand.input(for: settings, password: Self.awkwardPassword), encoding: .utf8)

        // Assert
        for command in commands {
            #expect(!command.contains("t3st"))
            #expect(!command.contains("PGPASSWORD="))
            #expect(!command.contains("--password"))
            #expect(!command.contains(" -p"))
        }
        #expect(input?.contains("t3st") == true)
    }

    @Test("Hive's scripts hold no single quote, so quoting them works in any shell the server's user has")
    func scriptsQuoteCleanly() {
        #expect(!DumpCommand.mysqlScript.contains("'"))
        #expect(!DumpCommand.postgresScript.contains("'"))
    }

    @Test("A database in a container is dumped through docker exec with its ID, and one on the host without docker")
    func containerAndHost() {
        // Arrange
        let container = DatabaseSettings(kind: .mysql, location: .container(serviceName: "site_db"), user: "site", name: "site")
        let host = DatabaseSettings(kind: .mysql, location: .host, user: "site", name: "site")

        // Act
        let inContainer = DumpCommand.dump(container, inContainer: Self.containerID)
        let onHost = DumpCommand.dump(host, inContainer: nil)

        // Assert
        #expect(inContainer.hasPrefix("'docker' 'exec' '--interactive' '\(Self.containerID)' 'sh' '-c' "))
        #expect(onHost.hasPrefix("'sh' '-c' "))
        #expect(inContainer.hasSuffix(" 'sh' 'site'"))
    }

    @Test("MySQL reads its user and password from an option file on standard input, with quotes and backslashes escaped")
    func mysqlOptionFile() {
        // Arrange
        let settings = DatabaseSettings(kind: .mysql, location: .host, user: "site", name: "site")

        // Act
        let input = String(bytes: DumpCommand.input(for: settings, password: Self.awkwardPassword), encoding: .utf8)

        // Assert
        #expect(input == #"""
        [client]
        user="site"
        password="Hive t3st: \"double\" 'single' \\back $HOME #hash"

        """#)
        let options = "--defaults-extra-file=/dev/stdin --single-transaction --routines --events --no-tablespaces"
        #expect(DumpCommand.mysqlScript.contains(options))
    }

    @Test("Postgres gets its password as one line, for the shell to read into PGPASSWORD")
    func postgresInput() {
        // Arrange
        let settings = DatabaseSettings(kind: .postgres, location: .host, user: "site", name: "site")

        // Act
        let input = DumpCommand.input(for: settings, password: Self.awkwardPassword)

        // Assert
        #expect(input == Data((Self.awkwardPassword + "\n").utf8))
        #expect(DumpCommand.postgresScript.contains("--format=custom --no-password --host=127.0.0.1"))
    }

    @Test("A word with a single quote is closed, escaped and reopened")
    func quoting() {
        #expect(DumpCommand.quoted("it's") == #"'it'\''s'"#)
        #expect(DumpCommand.quoted("$HOME") == "'$HOME'")
    }

    @Test("Dumps are named for their database, compressed for MySQL and in custom format for Postgres")
    func fileNames() {
        #expect(DumpCommand.fileName(for: DatabaseSettings(kind: .mysql, location: .host, user: "u", name: "shop$1")) == "shop$1.sql.gz")
        #expect(DumpCommand.fileName(for: DatabaseSettings(kind: .postgres, location: .host, user: "u", name: "site")) == "site.dump")
    }
}
