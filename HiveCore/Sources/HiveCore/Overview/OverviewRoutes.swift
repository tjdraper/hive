import Foundation
import HiveKit
import Hummingbird

enum OverviewRoutes {
    static func add(
        to router: Router<HiveRequestContext>,
        hiveID: UUID,
        settings: HiveSettingsStore,
        fullDiskAccess: @escaping @Sendable () -> FullDiskAccess
    ) {
        router.get(RouterPath(HiveEndpoint.overview)) { _, _ in
            let access = FullDiskAccessStatus(rawValue: fullDiskAccess().rawValue) ?? .unknown
            return try JSONResponse(HiveOverview(hiveID: hiveID, name: settings.settings().name, fullDiskAccess: access))
        }
    }
}
