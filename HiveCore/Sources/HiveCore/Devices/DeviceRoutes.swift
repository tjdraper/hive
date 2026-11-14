import Foundation
import HiveKit
import Hummingbird

enum DeviceRoutes {
    static func add(to router: Router<HiveRequestContext>, devices: DeviceStore, revocation: DeviceRevocationWorkflow) {
        router.get(RouterPath(HiveEndpoint.devices)) { _, _ in
            try JSONResponse(devices.all().map {
                DeviceSummary(id: $0.id, name: $0.name, pairedAt: $0.pairedAt, lastSeenAt: $0.lastSeenAt, build: $0.build)
            })
        }

        router.delete(RouterPath("\(HiveEndpoint.devices)/:id")) { _, context in
            guard let deviceID = context.parameters.get("id").flatMap(UUID.init(uuidString:)) else {
                return JSONResponse(status: .notFound)
            }
            let revoked = try revocation.revoke(deviceID, by: context.requireDevice())
            return JSONResponse(status: revoked ? .noContent : .notFound)
        }
    }
}
