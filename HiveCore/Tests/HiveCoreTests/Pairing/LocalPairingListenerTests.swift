import CryptoKit
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Testing
import XPC

/// Runs the listener without a Mach service, which only launchd can provide, and sends to it from this
/// same test process. The test runner has no team ID, so no requirement Beekeeper would meet can pass
/// here: the accepted path is checked in an installed build.
struct LocalPairingListenerTests {
    private let devices: DeviceStore
    private let workflow: LocalPairingWorkflow
    private let request = LocalPairingRequest(
        devicePublicKey: P256.Signing.PrivateKey().publicKey.x963Representation,
        deviceName: "Studio Mac"
    )

    init() throws {
        let database = try HiveDatabase.inMemory()
        devices = DeviceStore(database: database)
        workflow = LocalPairingWorkflow(
            hiveID: UUID(),
            pin: PublicKeyPin(publicKey: P256.Signing.PrivateKey().publicKey),
            settings: HiveSettingsStore(database: database, defaultPort: 4483),
            devices: devices,
            isRestarting: { false }
        )
    }

    private func send(to listener: LocalPairingListener) async throws -> LocalPairingResult {
        let session = try XPCSession(endpoint: listener.endpoint)
        defer { session.cancel(reason: "Test finished") }
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

    @Test("A sender that isn't Beekeeper is refused, and no device is recorded")
    func otherProgramIsRefused() async throws {
        // Arrange
        let listener = try LocalPairingListener(
            machService: nil,
            sender: .isFromSameTeam(andMatchesSigningIdentifier: "com.example.NotThisProgram"),
            workflow: workflow
        )
        defer { listener.cancel() }

        // Act
        let result = try await send(to: listener)

        // Assert
        #expect(result == .refused(.notBeekeeper))
        #expect(try await devices.database.writer.read { try PairedDevice.fetchCount($0) } == 0)
    }
}
