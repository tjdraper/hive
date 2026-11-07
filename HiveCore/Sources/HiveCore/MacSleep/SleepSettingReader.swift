import Foundation
import HiveKit
import os

/// Reads whether the Mac is set to sleep when idle, from `pmset -g`. macOS has no public API for the
/// setting.
struct SleepSettingReader: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "MacSleep")
    private static let pmset = URL(filePath: "/usr/bin/pmset")

    func read() async -> MacSleep {
        let command = ChildProcess(executableURL: Self.pmset, arguments: ["-g"], environment: [:])
        guard let result = try? await command.run(), result.status == 0,
              let output = String(bytes: result.standardOutput, encoding: .utf8)
        else {
            Self.logger.error("Couldn't run pmset to read the sleep setting")
            return .unknown
        }
        return Self.setting(in: output)
    }

    /// `SleepDisabled 1` turns sleep off whatever the timer says. Otherwise the `sleep` line under the
    /// settings in use gives minutes of idle before the Mac sleeps, and 0 for never. Assertions, Hive's
    /// own among them, are noted after the number and don't change it.
    static func setting(in output: String) -> MacSleep {
        var minutes: Int?
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, let value = Int(fields[1]) else { continue }
            switch fields[0] {
            case "SleepDisabled" where value != 0: return .never
            case "sleep": minutes = value
            default: continue
            }
        }
        guard let minutes, minutes >= 0 else { return .unknown }
        return minutes == 0 ? .never : .afterIdle(minutes: minutes)
    }
}
