import Foundation
import HiveKit

/// Which entries the job log shows.
struct JobLogFilter: Hashable {
    var serverID: UUID?
    var jobID: UUID?
    var problemsOnly = false

    /// The job log's path for the page after `before`, or the newest.
    func path(before: Int64?) -> String {
        var items: [URLQueryItem] = []
        if let before { items.append(URLQueryItem(name: "before", value: String(before))) }
        if let jobID {
            items.append(URLQueryItem(name: "job", value: jobID.uuidString))
        } else if let serverID {
            items.append(URLQueryItem(name: "server", value: serverID.uuidString))
        }
        if problemsOnly { items.append(URLQueryItem(name: "problems", value: "true")) }
        var components = URLComponents()
        components.path = HiveEndpoint.jobLog
        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? HiveEndpoint.jobLog
    }
}
