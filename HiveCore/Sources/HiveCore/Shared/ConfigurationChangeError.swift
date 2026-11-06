import HiveKit
import Hummingbird

/// A server or job Hive won't save, with every problem found.
enum ConfigurationChangeError: Error, Equatable {
    case refused([ConfigurationProblem])

    /// Answers 422 with the problems when `respond` is refused.
    static func answering(_ respond: () async throws -> JSONResponse) async throws -> JSONResponse {
        do {
            return try await respond()
        } catch ConfigurationChangeError.refused(let problems) {
            return try JSONResponse(ConfigurationRefusal(problems: problems), status: .unprocessableContent)
        }
    }
}
