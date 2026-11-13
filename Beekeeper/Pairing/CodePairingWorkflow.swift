import CryptoKit
import Foundation
import HiveKit
import os

enum CodePairingError: Error, Equatable {
    /// The Hive at the code's addresses showed the code's key but gave another Hive ID.
    case otherHive
}

/// Pairs this device with a Hive through a pairing code: a new Secure Enclave key for that Hive, sent
/// over a connection pinned to the key hash in the code, so no network is trusted for the Hive's key.
struct CodePairingWorkflow {
    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "Pairing")

    let keychain: DeviceKeychain

    /// `discovered` is where the code's Hive was found on the local network, tried before the code's addresses.
    func pair(_ code: PairingCode, deviceName: String, discovered: [HiveAddress]) async throws -> PairingResult {
        let key = try DeviceCredential.makeSigningKey()
        let request = PairingRequest(
            token: code.token,
            devicePublicKey: key.publicKey.x963Representation,
            deviceName: deviceName,
            apiVersions: .thisBuild
        )

        let result: PairingResult
        do {
            result = try await HiveConnection(addresses: code.addresses, pin: code.pin, discovered: discovered).pair(request)
        } catch {
            // A URLError's description names the host, which stays out of the system log.
            let kind = (error as? URLError).map { "URLError \($0.code.rawValue)" } ?? String(describing: error)
            Self.logger.error("Couldn't pair with a code: \(kind, privacy: .public)")
            throw error
        }
        guard result.hiveID == code.hiveID else {
            Self.logger.error("A Hive paired with a code gave another Hive ID")
            throw CodePairingError.otherHive
        }

        let credential = DeviceCredential(hiveID: result.hiveID, deviceID: result.deviceID, pin: code.pin, keyData: key.dataRepresentation)
        try keychain.save(credential)
        Self.logger.notice("Paired with a Hive through a code")
        return result
    }
}
