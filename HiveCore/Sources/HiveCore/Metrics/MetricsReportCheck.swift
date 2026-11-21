import Foundation
import ScoutProtocol

/// What Hive takes from a Scout in one report (§2), so a server that's been taken over can fill only
/// its own share of the store. Each limit is far above what a real server sends.
enum MetricsReportCheck {
    /// Many times a full batch from a real server.
    static let largestBody = 4 * 1024 * 1024
    static let largestFilesystemCount = 32
    static let largestDiskCount = 32
    static let largestInterfaceCount = 32
    /// Scout sends the top 10 groups by CPU and the top 10 by memory.
    static let largestProcessGroupCount = 20
    /// New filesystem, disk and interface names together, in any 24 hours.
    static let largestNewNameCountPerDay = 50
    static let largestNameBytes = 255
    /// A sample older than this by Hive's clock is left out.
    static let oldestSeconds: Int64 = 86_400
    /// How far ahead of Hive's clock, or of the time Scout reported sending at, a sample may be.
    static let largestLeadSeconds: Int64 = 5 * 60

    /// The samples and minutes Hive keeps from a report, leaving out those older than a day, or why
    /// it's refused whole.
    enum Outcome {
        case accepted(MetricsReport)
        case refused(ScoutRefusal.Reason)
    }

    static func checked(_ report: MetricsReport, at now: Int64) -> Outcome {
        guard report.samples.count <= MetricsReport.largestSampleCount, report.minutes.count <= MetricsReport.largestMinuteCount else {
            return .refused(.tooManySamples)
        }
        let times = report.samples.map(\.takenAt) + report.minutes.map(\.startsAt)
        let latest = min(now, report.sentAt) + largestLeadSeconds
        guard times.allSatisfy({ $0 <= latest }) else { return .refused(.clockAhead) }
        guard report.samples.allSatisfy(hasFewEnoughFigures), report.minutes.allSatisfy(hasFewEnoughFigures) else {
            return .refused(.tooManyFigures)
        }
        guard report.samples.allSatisfy(isInRange), report.minutes.allSatisfy(isInRange) else { return .refused(.valueOutOfRange) }

        // A backlog's oldest batch may cross the day while it's on its way, so the rest of it is kept.
        let oldest = now - oldestSeconds
        let kept = MetricsReport(
            protocolVersion: report.protocolVersion,
            sentAt: report.sentAt,
            samples: report.samples.filter { $0.takenAt >= oldest },
            minutes: report.minutes.filter { $0.startsAt >= oldest }
        )
        guard kept.samples.count + kept.minutes.count > 0 || times.isEmpty else { return .refused(.tooOld) }
        return .accepted(kept)
    }

    private static func hasFewEnoughFigures(_ sample: MetricsSample) -> Bool {
        sample.filesystems.count <= largestFilesystemCount
            && sample.disks.count <= largestDiskCount
            && sample.networkInterfaces.count <= largestInterfaceCount
            && (sample.processes?.groups.count ?? 0) <= largestProcessGroupCount
    }

    private static func hasFewEnoughFigures(_ minute: MetricsMinute) -> Bool {
        [minute.average, minute.highest].allSatisfy { figures in
            figures.filesystems.count <= largestFilesystemCount
                && figures.disks.count <= largestDiskCount
                && figures.networkInterfaces.count <= largestInterfaceCount
        } && minute.lowest.filesystems.count <= largestFilesystemCount
    }

    private static func isInRange(_ sample: MetricsSample) -> Bool {
        let processes = sample.processes.map { processes in
            isCount(processes.count) && isCount(processes.zombies) && processes.groups.allSatisfy { group in
                isName(group.command) && isName(group.user) && isCount(group.count)
                    && isRate(group.cpuCores) && isBytes(group.ownMemoryBytes)
            }
        } ?? true
        return processes && (sample.server.uptimeSeconds.map(isRate) ?? true)
            && isInRange(MinuteFigures(
                cpu: sample.cpu,
                memory: sample.memory,
                pressure: sample.pressure,
                filesystems: sample.filesystems,
                disks: sample.disks,
                networkInterfaces: sample.networkInterfaces
            ))
    }

    private static func isInRange(_ minute: MetricsMinute) -> Bool {
        (1 ... 60).contains(minute.sampleCount)
            && isInRange(minute.average)
            && isInRange(minute.highest)
            && isBytes(minute.lowest.memoryAvailableBytes)
            && minute.lowest.filesystems.allSatisfy { isName($0.mountPoint) && isBytes($0.availableBytes) && isBytes($0.inodesFree) }
    }

    private static func isInRange(_ figures: MinuteFigures) -> Bool {
        let cpu = figures.cpu.map { cpu in
            isCount(cpu.cores)
                && (cpu.use.map { [$0.user, $0.system, $0.ioWait, $0.steal].allSatisfy(isShare) } ?? true)
                && (cpu.load.map { [$0.oneMinute, $0.fiveMinutes, $0.fifteenMinutes].allSatisfy(isRate) } ?? true)
        } ?? true
        let memory = figures.memory.map { memory in
            [memory.totalBytes, memory.availableBytes, memory.cacheBytes, memory.swapTotalBytes, memory.swapUsedBytes].allSatisfy(isBytes)
                && (memory.swapping.map { isRate($0.pagesInPerSecond) && isRate($0.pagesOutPerSecond) } ?? true)
        } ?? true
        let pressure = figures.pressure.map { pressure in
            [pressure.cpu, pressure.memory, pressure.inputOutput].allSatisfy { stall in
                stall.map { isShare($0.some) && isShare($0.full) } ?? true
            }
        } ?? true
        let filesystems = figures.filesystems.allSatisfy { filesystem in
            isName(filesystem.mountPoint) && isName(filesystem.device) && isName(filesystem.type)
                && (filesystem.space.map { space in
                    [space.sizeBytes, space.usedBytes, space.availableBytes].allSatisfy(isBytes)
                        && isBytes(space.inodes?.used) && isBytes(space.inodes?.free)
                } ?? true)
        }
        let disks = figures.disks.allSatisfy { disk in
            isName(disk.name) && (disk.activity.map { activity in
                [activity.readBytesPerSecond, activity.writtenBytesPerSecond, activity.readsPerSecond, activity.writesPerSecond]
                    .allSatisfy(isRate) && isShare(activity.busy)
            } ?? true)
        }
        let interfaces = figures.networkInterfaces.allSatisfy { interface in
            isName(interface.name) && (interface.traffic.map { traffic in
                [
                    traffic.receivedBytesPerSecond, traffic.sentBytesPerSecond, traffic.receiveErrorsPerSecond,
                    traffic.sendErrorsPerSecond, traffic.receiveDropsPerSecond, traffic.sendDropsPerSecond,
                ].allSatisfy(isRate)
            } ?? true)
        }
        return cpu && memory && pressure && filesystems && disks && interfaces
    }

    /// Shown in Beekeeper and kept in the store, so a name is short and holds no control characters.
    static func isName(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= largestNameBytes
            && !text.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    private static func isShare(_ value: Double?) -> Bool {
        value.map { $0.isFinite && (0 ... 1).contains($0) } ?? true
    }

    /// Far above any real rate, and well within what SQLite keeps exactly enough.
    private static func isRate(_ value: Double?) -> Bool {
        value.map { $0.isFinite && (0 ... 1e15).contains($0) } ?? true
    }

    private static func isBytes(_ value: UInt64?) -> Bool {
        value.map { $0 <= UInt64(Int64.max) } ?? true
    }

    private static func isCount(_ value: Int) -> Bool {
        (0 ... 10_000_000).contains(value)
    }
}
