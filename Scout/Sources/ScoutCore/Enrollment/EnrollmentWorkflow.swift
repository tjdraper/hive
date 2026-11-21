#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Crypto
import ScoutProtocol

public enum EnrollmentError: Error, Equatable {
    /// Hive answered as if no window were open: the code expired, was used, or its window was closed.
    case codeRefused
    /// Too many codes that didn't work came from this server's address. It lasts a few minutes.
    case lockedOut
    case protocolNotAccepted(hiveVersion: Int)
    /// Hive accepted the token, but not the key Scout sent.
    case keyRefused
    /// Hive's answer named another Hive or server than the code did.
    case wrongHive
    case unexpectedStatus(UInt)
    case unreadableAnswer
}

/// Enrolls this server's Scout with a Hive through a code: makes a key, sends it to the first of the
/// code's addresses that answers with the pinned key, saves it, and signs in to check it works.
public struct EnrollmentWorkflow: Sendable {
    let connector: any HiveConnecting
    let store: EnrollmentStore

    public init(connector: any HiveConnecting, store: EnrollmentStore) {
        self.connector = connector
        self.store = store
    }

    public func enroll(with code: EnrollmentCode) async throws -> SavedEnrollment {
        // Enrolling uses up the code, so a folder Scout can't write in is found first.
        try store.checkWritable()
        let key = P256.Signing.PrivateKey()
        let fields = EnrollmentCodeFields(
            hiveID: code.hiveID,
            serverID: code.serverID,
            pin: code.pin,
            addresses: code.addresses.map { HiveAddress(host: $0.host, port: $0.port) }
        )
        let pin = HiveKeyPin(sha256: Array(code.pin))

        // A Hive that answered decides; only an address that couldn't be reached, or showed another
        // key, moves on to the next. Another key is what's reported, if any address showed one.
        var lastError: any Error = HiveConnectionError.closedByHive
        for address in fields.addresses {
            do {
                return try await connector.withConnection(to: address, pin: pin) { connection in
                    let enrollment = try await send(key, token: code.token, fields: fields, on: connection)
                    try store.save(enrollment)
                    var keeper = ScoutSessionKeeper(enrollment: enrollment)
                    try await keeper.checkSession(on: connection)
                    return enrollment
                }
            } catch let error as EnrollmentError {
                throw error
            } catch let error as ScoutSignInError {
                throw error
            } catch let error as PrivateFileError {
                throw error
            } catch {
                if lastError as? HiveConnectionError != .keyNotPinned { lastError = error }
            }
        }
        throw lastError
    }

    private func send(
        _ key: P256.Signing.PrivateKey,
        token: Data,
        fields: EnrollmentCodeFields,
        on connection: any HiveRequesting
    ) async throws -> SavedEnrollment {
        let request = ScoutEnrollmentRequest(
            token: token,
            scoutPublicKey: key.publicKey.x963Representation,
            protocolVersion: ScoutProtocolVersion.current
        )
        let answer = try await connection.send("POST", ScoutEndpoint.enrollment, body: Array(JSONEncoder().encode(request)), token: nil)
        switch answer.status {
        case 200: break
        case 404: throw EnrollmentError.codeRefused
        case 429: throw EnrollmentError.lockedOut
        case 422: throw EnrollmentError.keyRefused
        case 409:
            let mismatch = try? JSONDecoder().decode(ScoutProtocolMismatch.self, from: Data(answer.body))
            throw EnrollmentError.protocolNotAccepted(hiveVersion: mismatch?.hiveProtocolVersion ?? 0)
        default: throw EnrollmentError.unexpectedStatus(answer.status)
        }
        guard let enrolled = try? JSONDecoder().decode(ScoutEnrollment.self, from: Data(answer.body)) else {
            throw EnrollmentError.unreadableAnswer
        }
        guard enrolled.hiveID == fields.hiveID, enrolled.serverID == fields.serverID else { throw EnrollmentError.wrongHive }
        return SavedEnrollment(code: fields, scoutID: enrolled.scoutID, key: key)
    }
}
