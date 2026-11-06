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

    public static func device(_ id: UUID) -> String {
        "\(devices)/\(id.uuidString)"
    }
}
