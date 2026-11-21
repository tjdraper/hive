import Foundation

/// An open window for a server's Scout to enroll through, as the device that opened it shows it.
public struct EnrollmentWindow: Codable, Hashable, Sendable {
    public let id: UUID
    public let serverID: UUID
    /// The `scout1:` code `hive-scout enroll` reads. Hive never gives it out again.
    public let code: String
    public let expiresInSeconds: Int

    public init(id: UUID, serverID: UUID, code: String, expiresInSeconds: Int) {
        self.id = id
        self.serverID = serverID
        self.code = code
        self.expiresInSeconds = expiresInSeconds
    }
}

/// Sent with 422 when Hive won't open an enrollment window.
public struct EnrollmentWindowRefusal: Codable, Hashable, Sendable {
    public let problem: EnrollmentWindowProblem

    public init(problem: EnrollmentWindowProblem) {
        self.problem = problem
    }
}

public enum EnrollmentWindowProblem: String, Codable, Hashable, Sendable {
    /// A code without an address would give the Scout nowhere to reach the Hive.
    case noAddressOptions
}
