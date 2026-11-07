import Foundation
import IOKit.pwr_mgt
import os

/// Keeps the Mac from sleeping while something runs.
protocol SleepPreventing: Sendable {
    /// Returns what to call once the Mac may sleep again.
    func preventSleep() -> @Sendable () -> Void
}

/// A power assertion against idle sleep, as long as a backup runs. It shows in `pmset -g assertions`.
struct PowerAssertion: SleepPreventing {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Backup")

    func preventSleep() -> @Sendable () -> Void {
        var assertion = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Hive is running a backup" as CFString,
            &assertion
        )
        guard result == kIOReturnSuccess else {
            Self.logger.error("Couldn't keep the Mac awake for the run: IOReturn \(result, privacy: .public)")
            return { /* Nothing was taken to let go of. */ }
        }
        let id = assertion
        return { IOPMAssertionRelease(id) }
    }
}
