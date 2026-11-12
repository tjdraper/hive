import Foundation
import HiveKit
import Hummingbird

enum OverviewRoutes {
    static func add(to router: Router<HiveRequestContext>, api: HiveAPI) {
        router.get(RouterPath(HiveEndpoint.overview)) { _, _ in
            let access = FullDiskAccessStatus(rawValue: api.fullDiskAccess().rawValue) ?? .unknown
            let current = try api.settingsStore.settings()
            return try await JSONResponse(HiveOverview(
                hiveID: api.hiveID,
                name: current.name,
                fullDiskAccess: access,
                macSleep: api.macSleep(),
                addresses: current.addresses,
                version: api.version
            ))
        }
    }
}
