import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct BackupDriveRoutesTests {
    private let fixture: APIFixture
    private let temporary: TemporaryDirectory

    init() throws {
        fixture = try APIFixture()
        temporary = try TemporaryDirectory()
    }

    private func volumeFolder(_ name: String) throws -> URL {
        let url = temporary.url.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func choose(_ uuid: UUID) async throws -> APIAnswer {
        try await fixture.send(.put, HiveEndpoint.backupDrive, json: BackupDriveChoice(volumeUUID: uuid))
    }

    private func marker(on volume: URL) throws -> HiveDriveFolder.Marker {
        let data = try Data(contentsOf: volume.appending(path: "Hive/\(HiveDriveFolder.markerName)"))
        return try JSONDecoder().decode(HiveDriveFolder.Marker.self, from: data)
    }

    @Test("Choosing a case-sensitive APFS volume marks its Hive folder with the Hive ID and records the choice")
    func choosesDrive() async throws {
        // Arrange
        let volume = BackupRunFixture.volume(at: try volumeFolder("Drive"), uuid: UUID())
        fixture.volumes.set([volume])

        // Act
        let answer = try await choose(volume.uuid)

        // Assert
        #expect(answer.status == .ok)
        let state = try answer.decoded(as: BackupDriveState.self)
        let chosen = BackupDriveIdentity(volumeUUID: volume.uuid, name: "Test Drive")
        #expect(state.chosen == ChosenBackupDrive(drive: chosen, problem: nil))
        #expect(try marker(on: volume.url).hiveID == fixture.signIn.hiveID)
        #expect(try fixture.auditEvents().first == .backupDriveChosen(old: nil, new: chosen))
    }

    @Test("Choosing the drive already chosen records nothing new")
    func choosingAgainChangesNothing() async throws {
        // Arrange
        let volume = BackupRunFixture.volume(at: try volumeFolder("Drive"), uuid: UUID())
        fixture.volumes.set([volume])
        _ = try await choose(volume.uuid)
        let before = try fixture.auditEvents()

        // Act
        let answer = try await choose(volume.uuid)

        // Assert
        #expect(answer.status == .ok)
        #expect(try fixture.auditEvents() == before)
    }

    @Test(
        "A volume Hive can't keep snapshots on is refused, and nothing is written to it",
        arguments: [
            (false, false, BackupDriveProblem.notCaseSensitive),
            (true, true, .startupDisk),
        ]
    )
    func refusesUnsuitable(caseSensitive: Bool, startupDisk: Bool, problem: BackupDriveProblem) async throws {
        // Arrange
        let folder = try volumeFolder("Drive")
        let volume = BackupRunFixture.volume(at: folder, uuid: UUID(), caseSensitive: caseSensitive, startupDisk: startupDisk)
        fixture.volumes.set([volume])
        let before = try fixture.auditEvents()

        // Act
        let answer = try await choose(volume.uuid)

        // Assert
        #expect(answer.status == .unprocessableContent)
        #expect(try answer.decoded(as: BackupDriveRefusal.self).problem == problem)
        #expect(BackupRunFixture.contents(of: volume.url).isEmpty)
        #expect(try fixture.auditEvents() == before)
        #expect(try BackupDriveStore(database: fixture.signIn.database).chosen() == nil)
    }

    @Test("A volume that isn't mounted is refused")
    func refusesUnmounted() async throws {
        // Act
        let answer = try await choose(UUID())

        // Assert
        #expect(try answer.decoded(as: BackupDriveRefusal.self).problem == .notMounted)
    }

    @Test("A drive marked as another Hive's is refused, and its marker is left as it was")
    func refusesAnotherHivesDrive() async throws {
        // Arrange
        let volume = BackupRunFixture.volume(at: try volumeFolder("Drive"), uuid: UUID())
        fixture.volumes.set([volume])
        let otherHive = UUID()
        _ = HiveDriveFolder.claim(on: volume.url, hiveID: otherHive)

        // Act
        let answer = try await choose(volume.uuid)
        let state = try await fixture.send(.get, HiveEndpoint.backupDrive).decoded(as: BackupDriveState.self)

        // Assert
        #expect(try answer.decoded(as: BackupDriveRefusal.self).problem == .belongsToAnotherHive)
        #expect(try marker(on: volume.url).hiveID == otherHive)
        #expect(state.volumes.first?.problem == .belongsToAnotherHive)
    }

    @Test("A Hive folder that already holds something without a marker is refused")
    func refusesFolderInUse() async throws {
        // Arrange
        let folder = try volumeFolder("Drive")
        try FileManager.default.createDirectory(at: folder.appending(path: "Hive/someone else's"), withIntermediateDirectories: true)
        let volume = BackupRunFixture.volume(at: folder, uuid: UUID())
        fixture.volumes.set([volume])

        // Act
        let answer = try await choose(volume.uuid)

        // Assert
        #expect(try answer.decoded(as: BackupDriveRefusal.self).problem == .folderInUse)
        #expect(BackupRunFixture.contents(of: folder) == ["Hive", "Hive/someone else's"])
    }

    @Test("The Mac's volumes are listed with why Hive can't use each, and a chosen drive that's ejected shows as not mounted")
    func listsVolumes() async throws {
        // Arrange
        let good = BackupRunFixture.volume(at: try volumeFolder("Good"), uuid: UUID())
        let insensitive = BackupRunFixture.volume(at: try volumeFolder("Insensitive"), uuid: UUID(), caseSensitive: false)
        fixture.volumes.set([good, insensitive])
        _ = try await choose(good.uuid)
        fixture.volumes.set([insensitive])

        // Act
        let state = try await fixture.send(.get, HiveEndpoint.backupDrive).decoded(as: BackupDriveState.self)

        // Assert
        #expect(state.chosen?.problem == .notMounted)
        #expect(state.volumes.map(\.problem) == [.notCaseSensitive])
    }

    @Test("A drive can't be chosen without signing in, and nothing is written to it")
    func refusedWithoutSigningIn() async throws {
        // Arrange
        let volume = BackupRunFixture.volume(at: try volumeFolder("Drive"), uuid: UUID())
        fixture.volumes.set([volume])
        let body = ByteBuffer(bytes: try JSONEncoder().encode(BackupDriveChoice(volumeUUID: volume.uuid)))

        // Act
        try await fixture.application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.backupDrive, method: .put, body: body) { response in
                // Assert
                #expect(response.status == .unauthorized)
            }
        }

        // Assert
        #expect(BackupRunFixture.contents(of: volume.url).isEmpty)
        #expect(try BackupDriveStore(database: fixture.signIn.database).chosen() == nil)
    }
}
