import Foundation
import HiveKit
import Hummingbird

enum JobLogRoutes {
    static let defaultPageSize = 100

    static func add(to router: Router<HiveRequestContext>, jobLog: JobLog) {
        router.get(RouterPath(HiveEndpoint.jobLog)) { request, _ in
            let parameters = request.uri.queryParameters
            let before = parameters.get("before", as: Int64.self)
            let limit = parameters.get("limit", as: Int.self) ?? defaultPageSize
            // A filter that can't be read would otherwise give every job's runs.
            guard let jobID = uuid(parameters.get("job")), let serverID = uuid(parameters.get("server")) else {
                return JSONResponse(status: .badRequest)
            }
            return try JSONResponse(jobLog.page(before: before, limit: limit, jobID: jobID, serverID: serverID))
        }
    }

    /// `.some(nil)` when there's no parameter, and nil when it isn't an ID.
    private static func uuid(_ parameter: String?) -> UUID?? {
        guard let parameter else { return .some(nil) }
        return UUID(uuidString: parameter).map { .some($0) }
    }
}
