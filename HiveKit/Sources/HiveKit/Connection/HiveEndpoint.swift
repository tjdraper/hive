import Foundation

public enum HiveEndpoint {
    public static let health = "/health"
    public static let signInChallenge = "/sign-in/challenge"
    public static let signIn = "/sign-in"
    public static let overview = "/hive"
    public static let devices = "/devices"
    public static let settings = "/settings"
    /// Newest first. `?before=<entry ID>` gives the page after one already shown.
    public static let auditLog = "/audit-log"

    public static let servers = "/servers"
    /// Every server's jobs. A job is added under its server, with `jobs(onServer:)`.
    public static let jobs = "/jobs"

    public static func device(_ id: UUID) -> String {
        "\(devices)/\(id.uuidString)"
    }

    public static func server(_ id: UUID) -> String {
        "\(servers)/\(id.uuidString)"
    }

    /// `GET` reads Hive's SSH key for the server, and `POST` makes a new one.
    public static func sshKey(onServer id: UUID) -> String {
        "\(server(id))/ssh-key"
    }

    /// `POST` scans the server's host key without recording it.
    public static func hostKeyScan(onServer id: UUID) -> String {
        "\(hostKey(onServer: id))/scan"
    }

    /// `PUT` records the key the last scan found.
    public static func hostKey(onServer id: UUID) -> String {
        "\(server(id))/host-key"
    }

    /// `POST` connects with Hive's key and runs a command that changes nothing.
    public static func connectionTest(onServer id: UUID) -> String {
        "\(server(id))/connection-test"
    }

    public static func jobs(onServer id: UUID) -> String {
        "\(server(id))\(jobs)"
    }

    public static func job(_ id: UUID) -> String {
        "\(jobs)/\(id.uuidString)"
    }
}
