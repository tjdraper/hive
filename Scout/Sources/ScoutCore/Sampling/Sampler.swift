import ScoutProtocol

/// Takes a server's samples. It keeps the previous readings that rates are worked out from, so one
/// sampler serves a run of samples.
public struct Sampler {
    private let serverFacts: ServerFactsReader

    public init(files: SystemFiles = SystemFiles()) {
        serverFacts = ServerFactsReader(files: files)
    }

    /// - Parameter takenAt: the sample's mark, in seconds since 1970.
    public mutating func sample(takenAt: Int64) -> MetricsSample {
        MetricsSample(takenAt: takenAt, server: serverFacts.read())
    }
}
