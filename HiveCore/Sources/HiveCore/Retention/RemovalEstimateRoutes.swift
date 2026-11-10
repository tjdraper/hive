import Foundation
import HiveKit
import Hummingbird

enum RemovalEstimateRoutes {
    static func add(to router: Router<HiveRequestContext>, estimator: RemovalEstimator) {
        router.post(RouterPath("\(HiveEndpoint.servers)/:id/quota-estimate")) { request, context in
            let asked = try await JSONRequest.decode(QuotaEstimateRequest.self, from: request)
            guard let id = context.idParameter, let estimate = try estimator.estimate(quotaBytes: asked.quotaBytes, ofServer: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(estimate)
        }

        router.post(RouterPath("\(HiveEndpoint.jobs)/:id/retention-estimate")) { request, context in
            let tiers = try await JSONRequest.decode(RetentionTiers.self, from: request)
            guard let id = context.idParameter, let estimate = try estimator.estimate(tiers: tiers, ofJob: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(estimate)
        }
    }
}
