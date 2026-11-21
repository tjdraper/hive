public struct CPUFigures: Codable, Hashable, Sendable {
    public var cores: Int
    /// Missing from the first sample.
    public var use: CPUUse?
    public var load: LoadAverages?

    public init(cores: Int, use: CPUUse?, load: LoadAverages?) {
        self.cores = cores
        self.use = use
        self.load = load
    }
}

/// How the time of every core together was spent since the previous sample, each a share from 0 to 1.
/// The rest was idle.
public struct CPUUse: Codable, Hashable, Sendable {
    /// Includes work at a lower priority (`nice`).
    public var user: Double
    /// Includes handling interrupts.
    public var system: Double
    /// Idle while waiting for a disk.
    public var ioWait: Double
    /// Taken by a virtual server's host for someone else.
    public var steal: Double

    public init(user: Double, system: Double, ioWait: Double, steal: Double) {
        self.user = user
        self.system = system
        self.ioWait = ioWait
        self.steal = steal
    }
}

/// The kernel's average number of tasks running or waiting to run, which ``CPUFigures/cores`` puts in proportion.
public struct LoadAverages: Codable, Hashable, Sendable {
    public var oneMinute: Double
    public var fiveMinutes: Double
    public var fifteenMinutes: Double

    public init(oneMinute: Double, fiveMinutes: Double, fifteenMinutes: Double) {
        self.oneMinute = oneMinute
        self.fiveMinutes = fiveMinutes
        self.fifteenMinutes = fifteenMinutes
    }
}
