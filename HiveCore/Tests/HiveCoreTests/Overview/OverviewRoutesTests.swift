import Darwin
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct OverviewRoutesTests {
    private let fixture: APIFixture

    init() throws {
        fixture = try APIFixture()
    }

    private func overview() async throws -> HiveOverview {
        let token = try fixture.token()
        return try await fixture.application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.overview, method: .get, headers: fixture.headers(token: token)) { response in
                #expect(response.status == .ok)
                return try response.decoded(as: HiveOverview.self)
            }
        }
    }

    @Test("The overview gives the Hive's ID and name")
    func givesIDAndName() async throws {
        // Act
        let overview = try await overview()

        // Assert
        #expect(overview.hiveID == fixture.signIn.hiveID)
        #expect(overview.name == "Test Hive")
        #expect(overview.fullDiskAccess == .granted)
    }

    @Test("Full Disk Access is checked at each request, so turning it off shows at once")
    func checksFullDiskAccessEachTime() async throws {
        // Arrange
        let before = try await overview()

        // Act
        fixture.fullDiskAccess.set(EPERM)
        let after = try await overview()

        // Assert
        #expect(before.fullDiskAccess == .granted)
        #expect(after.fullDiskAccess == .missing)
    }
}
