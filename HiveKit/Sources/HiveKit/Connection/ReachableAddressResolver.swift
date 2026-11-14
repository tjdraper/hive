import Foundation

/// Finds which of a Hive's addresses it answers at by asking them all at once and taking the first to
/// answer, so an address on a network the device isn't on costs nothing while another one answers.
///
/// Anything on the local network can advertise any Hive, so another key shown at a discovered address
/// says nothing about the Hive's identity, and counts as the Hive not being there. Another key at one of
/// the Hive's own addresses, with none answering, is the Hive's identity having changed.
struct ReachableAddressResolver: Sendable {
    struct Candidate: Sendable, Equatable {
        let address: HiveAddress
        /// Found on the local network (`LocalNetworkService`) rather than one of the Hive's own addresses.
        let isDiscovered: Bool
    }

    private enum Answer: Sendable {
        case answered(HiveAddress)
        case failed(Candidate, any Error)
    }

    let candidates: [Candidate]
    /// Throws when the Hive can't be reached at the address or shows another key there.
    let probe: @Sendable (HiveAddress) async throws -> Void

    func firstToAnswer() async throws -> HiveAddress {
        guard !candidates.isEmpty else { throw HiveConnectionError.invalidAddress }
        let result = await withTaskGroup(of: Answer.self) { group -> Result<HiveAddress, any Error> in
            for candidate in candidates {
                group.addTask {
                    do {
                        try await probe(candidate.address)
                        return .answered(candidate.address)
                    } catch {
                        return .failed(candidate, error)
                    }
                }
            }
            var lastError: (any Error)?
            var sawWrongKey = false
            for await answer in group {
                switch answer {
                case .answered(let address):
                    group.cancelAll()
                    return .success(address)
                case .failed(let candidate, HiveConnectionError.wrongKey) where candidate.isDiscovered:
                    lastError = lastError ?? URLError(.cannotConnectToHost)
                case .failed(_, HiveConnectionError.wrongKey):
                    sawWrongKey = true
                case .failed(_, let error):
                    lastError = error
                }
            }
            if sawWrongKey { return .failure(HiveConnectionError.wrongKey) }
            return .failure(lastError ?? HiveConnectionError.invalidAddress)
        }
        try Task.checkCancellation()
        return try result.get()
    }
}
