#if os(macOS)
import CryptoKit
import Foundation
import HiveKit
import os
import XPC

enum LocalPairingError: Error {
    case unreachable
    case refused(LocalPairingRefusal)
}

/// Pairs Beekeeper with the Hive on this Mac, over XPC, with no code to enter: Hive checks this app's
/// signature instead.
struct LocalPairingWorkflow {
    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "Pairing")

    let keychain: DeviceKeychain

    func pair() async throws -> LocalPairing {
        let service = try LocalHiveService.read()
        let key = try DeviceCredential.makeSigningKey()
        let request = LocalPairingRequest(
            devicePublicKey: key.publicKey.x963Representation,
            deviceName: Host.current().localizedName ?? "Mac"
        )

        let result: LocalPairingResult
        do {
            result = try await Self.send(request, to: service)
        } catch {
            Self.logger.error("Couldn't reach this Mac's Hive: \(String(describing: error), privacy: .public)")
            throw LocalPairingError.unreachable
        }

        switch result {
        case .refused(let refusal):
            Self.logger.error("This Mac's Hive refused to pair: \(refusal.rawValue, privacy: .public)")
            throw LocalPairingError.refused(refusal)
        case .paired(let pairing):
            try keychain.save(DeviceCredential(
                hiveID: pairing.hiveID,
                deviceID: pairing.deviceID,
                pin: pairing.pin,
                keyData: key.dataRepresentation
            ))
            Self.logger.notice("Paired with this Mac's Hive")
            return pairing
        }
    }

    private nonisolated static func send(_ request: LocalPairingRequest, to service: LocalHiveService) async throws -> LocalPairingResult {
        let session = try XPCSession(
            machService: service.machService,
            requirement: .isFromSameTeam(andMatchesSigningIdentifier: service.daemonSigningIdentifier)
        )
        defer { session.cancel(reason: "Pairing finished") }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.send(request) { (result: Result<LocalPairingResult, any Error>) in
                    continuation.resume(with: result)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
