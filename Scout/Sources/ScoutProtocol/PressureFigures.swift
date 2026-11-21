/// The kernel's pressure stall figures (`/proc/pressure`) since the previous sample.
public struct PressureFigures: Codable, Hashable, Sendable {
    public var cpu: PressureStall?
    public var memory: PressureStall?
    /// Disk and other input and output.
    public var inputOutput: PressureStall?

    public init(cpu: PressureStall?, memory: PressureStall?, inputOutput: PressureStall?) {
        self.cpu = cpu
        self.memory = memory
        self.inputOutput = inputOutput
    }
}

/// Shares of time, from 0 to 1, that work was stalled waiting for one resource.
public struct PressureStall: Codable, Hashable, Sendable {
    /// At least one task was waiting.
    public var some: Double
    /// Every task that wasn't idle was waiting. Missing where the kernel doesn't report it, as for CPU
    /// before Linux 5.13.
    public var full: Double?

    public init(some: Double, full: Double?) {
        self.some = some
        self.full = full
    }
}
