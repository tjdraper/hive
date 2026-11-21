import ScoutProtocol

/// Reads the kernel's pressure figures where `/proc/pressure` exists. It needs Linux 4.20 or later
/// and can be turned off when the kernel is built or started, so a server without it sends none.
struct PressureReader {
    private struct Totals: Equatable {
        var cpu: PressureTotals?
        var memory: PressureTotals?
        var inputOutput: PressureTotals?
    }

    let files: SystemFiles
    private var previous: Totals?

    init(files: SystemFiles) {
        self.files = files
    }

    /// - Parameter elapsed: seconds since the previous reading, nil when there's none to compare with.
    mutating func read(elapsed: Double?) -> PressureFigures? {
        let totals = Totals(
            cpu: files.text(at: "/proc/pressure/cpu").flatMap(PressureTotals.init(parsing:)),
            memory: files.text(at: "/proc/pressure/memory").flatMap(PressureTotals.init(parsing:)),
            inputOutput: files.text(at: "/proc/pressure/io").flatMap(PressureTotals.init(parsing:))
        )
        guard totals.cpu != nil || totals.memory != nil || totals.inputOutput != nil else {
            previous = nil
            return nil
        }
        defer { previous = totals }
        guard let previous, let elapsed else { return nil }
        return PressureFigures(
            cpu: Self.stall(from: previous.cpu, to: totals.cpu, seconds: elapsed),
            memory: Self.stall(from: previous.memory, to: totals.memory, seconds: elapsed),
            inputOutput: Self.stall(from: previous.inputOutput, to: totals.inputOutput, seconds: elapsed)
        )
    }

    /// The share of `seconds` that work was stalled. Capped at 1, since the kernel's totals and its
    /// uptime aren't read at the same instant.
    static func stall(from previous: PressureTotals?, to current: PressureTotals?, seconds: Double) -> PressureStall? {
        guard let previous, let current,
              let some = CounterIncrease.of(previous.some, to: current.some)
        else { return nil }
        let share = { (microseconds: UInt64) in min(1, Double(microseconds) / 1_000_000 / seconds) }
        let full = previous.full.flatMap { earlier in current.full.flatMap { CounterIncrease.of(earlier, to: $0) } }
        return PressureStall(some: share(some), full: full.map(share))
    }
}
