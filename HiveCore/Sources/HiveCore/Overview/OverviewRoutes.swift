import Foundation
import HiveKit
import Hummingbird

enum OverviewRoutes {
    static func add(
        to router: Router<HiveRequestContext>,
        hiveID: UUID,
        settings: HiveSettingsStore,
        fullDiskAccess: @escaping @Sendable () -> FullDiskAccess,
        macSleep: @escaping @Sendable () async -> MacSleep
    ) {
        router.get(RouterPath(HiveEndpoint.overview)) { _, _ in
            let access = FullDiskAccessStatus(rawValue: fullDiskAccess().rawValue) ?? .unknown
            let current = try settings.settings()
            return try await JSONResponse(HiveOverview(
                hiveID: hiveID,
                name: current.name,
                fullDiskAccess: access,
                macSleep: macSleep(),
                addresses: current.addresses
            ))
        }
    }
}
