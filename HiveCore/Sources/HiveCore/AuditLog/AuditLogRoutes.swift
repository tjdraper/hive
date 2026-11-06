import Foundation
import HiveKit
import Hummingbird

enum AuditLogRoutes {
    static let defaultPageSize = 100

    static func add(to router: Router<HiveRequestContext>, auditLog: AuditLog) {
        router.get(RouterPath(HiveEndpoint.auditLog)) { request, _ in
            let before = request.uri.queryParameters.get("before", as: Int64.self)
            let limit = request.uri.queryParameters.get("limit", as: Int.self) ?? defaultPageSize
            return try JSONResponse(auditLog.page(before: before, limit: limit))
        }
    }
}
