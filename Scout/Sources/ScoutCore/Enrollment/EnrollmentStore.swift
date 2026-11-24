#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Crypto
import ScoutProtocol

/// What a Scout keeps from enrolling: its key, and which Hive and server it reports to and for.
public struct SavedEnrollment: Codable, Equatable, Sendable {
    public struct Address: Codable, Equatable, Sendable {
        public let host: String
        public let port: Int
    }

    public let hiveID: UUID
    public let serverID: UUID
    public let scoutID: UUID
    /// The SHA-256 hash of Hive's identity key in its X9.63 form.
    public let pin: Data
    /// In the order to try them.
    public internal(set) var addresses: [Address]
    /// The raw form of the Scout's P-256 key.
    let privateKey: Data

    init(code: EnrollmentCodeFields, scoutID: UUID, key: P256.Signing.PrivateKey) {
        hiveID = code.hiveID
        serverID = code.serverID
        self.scoutID = scoutID
        pin = code.pin
        addresses = code.addresses.map { Address(host: $0.host, port: $0.port) }
        privateKey = key.rawRepresentation
    }

    public var hivePin: HiveKeyPin {
        HiveKeyPin(sha256: Array(pin))
    }

    public var hiveAddresses: [HiveAddress] {
        addresses.map { HiveAddress(host: $0.host, port: $0.port) }
    }

    func signingKey() throws -> P256.Signing.PrivateKey {
        try P256.Signing.PrivateKey(rawRepresentation: privateKey)
    }
}

/// The parts of an enrollment code a Scout keeps, so tests can make one without a token.
struct EnrollmentCodeFields {
    let hiveID: UUID
    let serverID: UUID
    let pin: Data
    let addresses: [HiveAddress]
}

public enum AddressChangeError: Error, Equatable {
    case notEnrolled
    case unreadable(String)
    case unwritable(String)
}

/// The file in Scout's state folder holding its enrollment, readable only by the user Scout runs as.
public struct EnrollmentStore: Sendable {
    public static let defaultDirectory = "/var/lib/hive-scout"
    static let fileName = "enrollment.json"

    let path: String

    public init(directory: String = Self.defaultDirectory) {
        path = (directory.hasSuffix("/") ? String(directory.dropLast()) : directory) + "/" + Self.fileName
    }

    /// Nil when this Scout hasn't enrolled.
    public func load() throws -> SavedEnrollment? {
        try PrivateFile.read(path).map { try JSONDecoder().decode(SavedEnrollment.self, from: Data($0)) }
    }

    /// Replaces any enrollment saved before, so a server can move to another Hive or enroll again.
    func save(_ enrollment: SavedEnrollment) throws {
        try PrivateFile.write(Array(JSONEncoder().encode(enrollment)), to: path)
    }

    /// Keeps the key and the pin, so the Scout still talks only to the Hive it enrolled with.
    public func replaceAddresses(with addresses: [EnrollmentCode.Address]) throws(AddressChangeError) {
        let saved: SavedEnrollment?
        do {
            saved = try load()
        } catch {
            throw .unreadable(String(describing: error))
        }
        guard var enrollment = saved else { throw .notEnrolled }
        enrollment.addresses = addresses.map { SavedEnrollment.Address(host: $0.host, port: $0.port) }
        do {
            try save(enrollment)
        } catch {
            throw .unwritable(String(describing: error))
        }
    }

    func checkWritable() throws {
        try PrivateFile.checkWritable(beside: path)
    }
}
