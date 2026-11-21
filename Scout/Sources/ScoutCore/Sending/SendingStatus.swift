#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Where a running Scout's sending stands, which `hive-scout status` prints.
public struct SendingStatus: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case connecting
        case sending
        case unreachable
        /// Hive turned this Scout away for good, such as after it was removed, until it enrolls again
        /// or is updated.
        case refused
    }

    public var state: State = .connecting
    /// Why it's unreachable or refused.
    public var problem: String?
    /// Seconds since 1970.
    public var lastDeliveredAt: Int64?
    /// Why Hive refused the last samples it turned away, when it hasn't taken any since.
    public var lastRefusal: String?
    public var heldSamples = 0
    public var heldMinutes = 0
    /// Seconds since 1970. A running Scout updates it with every sample.
    public var updatedAt: Int64 = 0

    public init() {}
}

/// The running Scout's status, in its runtime folder, which is in memory, so writing it with every
/// sample doesn't write to disk (§3).
public struct SendingStatusFile: Sendable {
    public static let defaultDirectory = "/run/hive-scout"
    static let fileName = "status.json"

    let path: String

    public init(directory: String = Self.defaultDirectory) {
        path = (directory.hasSuffix("/") ? String(directory.dropLast()) : directory) + "/" + Self.fileName
    }

    /// Nil when no Scout has written one.
    public func load() throws -> SendingStatus? {
        try PrivateFile.read(path).map { try JSONDecoder().decode(SendingStatus.self, from: Data($0)) }
    }

    public func save(_ status: SendingStatus) throws {
        try PrivateFile.write(Array(JSONEncoder().encode(status)), to: path)
    }
}
