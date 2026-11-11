import Foundation
import HiveKit

/// Every command Hive runs on a server to find and dump a database is built here. `ssh` hands each to
/// the server's shell as one line, so every part of it is quoted. The password is never in a command:
/// it goes to the dump through standard input (§11).
enum DumpCommand {
    /// Docker's own labels for the service a container belongs to.
    static let swarmServiceLabel = "com.docker.swarm.service.name"
    static let composeServiceLabel = "com.docker.compose.service"

    /// The running containers, one a line: the full ID, then its Swarm and Compose service names,
    /// separated by tabs and empty where it has none.
    static func containerList() -> String {
        let format = #"{{.ID}}\t{{.Label "\#(swarmServiceLabel)"}}\t{{.Label "\#(composeServiceLabel)"}}"#
        return RemoteCommandLine.line(["docker", "ps", "--no-trunc", "--format", format])
    }

    /// `containerID` is nil for a database on the host.
    static func dump(_ settings: DatabaseSettings, inContainer containerID: String?) -> String {
        let script: String
        let arguments: [String]
        switch settings.kind {
        case .mysql:
            (script, arguments) = (mysqlScript, [settings.name])
        case .postgres:
            (script, arguments) = (postgresScript, [settings.user, settings.name])
        }
        // `sh` fills `$0`, so the arguments start at `$1`.
        let shell = ["sh", "-c", script, "sh"] + arguments
        guard let containerID else { return RemoteCommandLine.line(shell) }
        return RemoteCommandLine.line(["docker", "exec", "--interactive", containerID] + shell)
    }

    /// What the dump reads from standard input before it starts, which holds the password.
    static func input(for settings: DatabaseSettings, password: String) -> Data {
        switch settings.kind {
        case .mysql:
            Data("[client]\nuser=\(optionValue(settings.user))\npassword=\(optionValue(password))\n".utf8)
        case .postgres:
            Data((password + "\n").utf8)
        }
    }

    /// MariaDB 11's images have only `mariadb-dump`, and MySQL's only `mysqldump`. Each reads its user
    /// and password from an option file, here standard input, which has to be its first option.
    /// `--single-transaction` dumps from one consistent view without locking tables the site is still
    /// writing to, and `--no-tablespaces` lets a user without the PROCESS privilege dump on MySQL 8.
    static let mysqlScript = """
    for tool in mariadb-dump mysqldump; do \
    if command -v "$tool" >/dev/null 2>&1; then \
    exec "$tool" --defaults-extra-file=/dev/stdin --single-transaction --routines --events --no-tablespaces "$1"; \
    fi; \
    done; \
    echo "Hive: no mariadb-dump or mysqldump" >&2; exit \(DumpResultReader.toolMissingStatus)
    """

    /// pg_dump can't read a password from standard input itself, and refuses a password file that
    /// isn't a regular file, so the shell reads it into `PGPASSWORD`, which no command line shows.
    /// It connects over TCP to `127.0.0.1`, since the images trust every connection through the local socket.
    static let postgresScript = """
    IFS= read -r PGPASSWORD; export PGPASSWORD; \
    exec pg_dump --format=custom --no-password --host=127.0.0.1 --username="$1" --dbname="$2"
    """

    /// The file a database's dump is kept in within `databases/`. C1 keeps names to plain characters.
    static func fileName(for settings: DatabaseSettings) -> String {
        switch settings.kind {
        case .mysql: "\(settings.name).sql.gz"
        case .postgres: "\(settings.name).dump"
        }
    }

    /// In double quotes, so spaces at either end and `#` stay part of it. MySQL and MariaDB read `\\`
    /// and `\"` back as the characters.
    static func optionValue(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
