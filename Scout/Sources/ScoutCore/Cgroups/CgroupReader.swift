import ScoutProtocol

/// Reads each Docker container's and systemd service's cgroup (§4), keeping its counters to work out
/// rates at the next reading, and which unit each process is in.
///
/// Like a process's files, each unit's are kept open and read again from the start, since opening and
/// closing them for every unit each sample would cost more than reading them. A unit's files stay tied
/// to the cgroup they were opened in: once it's removed, as when a service restarts, reading fails and
/// they're opened again by path.
final class CgroupReader {
    struct Reading {
        var containers: [CgroupUse]
        var services: [CgroupUse]
        /// The unit each process listed in a unit's `cgroup.procs` is in. A process in a cgroup of its
        /// own below a unit's isn't listed.
        var unitOfProcess: [Int32: CgroupUnit]
    }

    /// Units whose files are kept open. The rest are opened for each reading.
    static let heldUnitLimit = 100
    static let filesPerUnit = 5
    static let topCountByEachMeasure = 10

    private struct Counters {
        var cpuNanoseconds: UInt64?
        var inputOutput: (read: UInt64, written: UInt64)?
    }

    /// Nil for a file the unit doesn't have, such as `io.stat` where the `io` controller isn't on.
    private struct Files {
        var processes: Int32
        var cpu: Int32?
        var memory: Int32?
        var memoryStat: Int32?
        var inputOutput: Int32?

        var all: [Int32] {
            [processes] + [cpu, memory, memoryStat, inputOutput].compactMap(\.self)
        }
    }

    let files: SystemFiles
    private var layout: CgroupLayout?
    private var held: [CgroupUnit: Files] = [:]
    private var previous: [CgroupUnit: Counters] = [:]
    /// Reused for every file.
    private var buffer = [UInt8](repeating: 0, count: 4096)

    init(files: SystemFiles) {
        self.files = files
    }

    deinit {
        for unitFiles in held.values {
            close(unitFiles)
        }
    }

    /// Nil where the server has no cgroups Scout can read.
    ///
    /// - Parameter elapsed: seconds since the previous reading, nil when there's none to compare with.
    func read(elapsed: Double?) -> Reading? {
        if layout == nil { layout = CgroupLayout.detect(in: files) }
        guard let layout else { return nil }

        var reading = Reading(containers: [], services: [], unitOfProcess: [:])
        var counters: [CgroupUnit: Counters] = [:]
        for unit in units(in: layout) {
            // A unit removed between listing and reading is skipped.
            guard let opened = open(unit, in: layout) else { continue }
            let unitFiles = opened.files
            let pids = opened.processIDs
            for pid in pids {
                reading.unitOfProcess[pid] = unit
            }
            let current = Counters(
                cpuNanoseconds: unitFiles.cpu.flatMap { read($0) { bytes in layout.version == .version2
                    ? CgroupFiles.cpuMicroseconds(parsing: bytes).map { $0 &* 1_000 }
                    : CgroupFiles.number(parsing: bytes)
                } },
                inputOutput: unitFiles.inputOutput.flatMap { read($0) { bytes in layout.version == .version2
                    ? CgroupFiles.inputOutput(parsingV2: bytes)
                    : CgroupFiles.inputOutput(parsingV1: bytes)
                } }
            )
            counters[unit] = current
            // A unit that appeared since the previous reading, or whose cgroup was made again, did all
            // its work in between.
            let earlier = opened.isNew || previous[unit] == nil ? Counters(cpuNanoseconds: 0, inputOutput: (0, 0)) : previous[unit]
            let use = CgroupUse(
                name: unit.name,
                cpuCores: rate(earlier?.cpuNanoseconds, current.cpuNanoseconds, elapsed: elapsed).map { $0 / 1e9 },
                memoryBytes: memory(of: unitFiles, in: layout),
                readBytesPerSecond: rate(earlier?.inputOutput?.read, current.inputOutput?.read, elapsed: elapsed),
                writtenBytesPerSecond: rate(earlier?.inputOutput?.written, current.inputOutput?.written, elapsed: elapsed),
                processes: pids.count,
                commands: []
            )
            switch unit.kind {
            case .container: reading.containers.append(use)
            case .service: reading.services.append(use)
            }
            if held[unit] == nil { close(unitFiles) }
        }
        for unit in held.keys where counters[unit] == nil {
            closeHeld(unit)
        }
        previous = counters
        return reading
    }

    /// The top units by CPU and by memory, each once, with each container's commands.
    static func figures(of uses: [CgroupUse], commands: [String: [String]] = [:]) -> CgroupFigures {
        let byCPU = uses.sorted { ($0.cpuCores ?? 0, $0.memoryBytes ?? 0, $1.name) > ($1.cpuCores ?? 0, $1.memoryBytes ?? 0, $0.name) }
        let byMemory = uses.sorted { ($0.memoryBytes ?? 0, $1.name) > ($1.memoryBytes ?? 0, $0.name) }
        var chosen: Set<String> = []
        var top: [CgroupUse] = []
        for use in byCPU.prefix(topCountByEachMeasure) + byMemory.prefix(topCountByEachMeasure) where chosen.insert(use.name).inserted {
            var use = use
            use.commands = commands[use.name] ?? []
            top.append(use)
        }
        return CgroupFigures(count: uses.count, top: top)
    }

    private func units(in layout: CgroupLayout) -> [CgroupUnit] {
        var units: [CgroupUnit] = []
        for folder in CgroupLayout.unitFolders {
            for entry in files.entries(in: "\(layout.listingRoot)/\(folder)") ?? [] {
                if let unit = CgroupLayout.unit(named: entry, in: folder) {
                    units.append(unit)
                } else if folder == "system.slice", entry.hasSuffix(".slice") {
                    let slice = "\(folder)/\(entry)"
                    let entries = files.entries(in: "\(layout.listingRoot)/\(slice)") ?? []
                    units += entries.compactMap { CgroupLayout.unit(named: $0, in: slice) }
                }
            }
        }
        return units
    }

    private struct Opened {
        let files: Files
        /// From its `cgroup.procs`.
        let processIDs: [Int32]
        /// Opened for a cgroup made since the previous reading.
        let isNew: Bool
    }

    /// Held files that no longer read are of a cgroup that was removed.
    private func open(_ unit: CgroupUnit, in layout: CgroupLayout) -> Opened? {
        var isNew = false
        if let unitFiles = held[unit] {
            if let ids = read(unitFiles.processes, CgroupFiles.processIDs(parsing:)) {
                return Opened(files: unitFiles, processIDs: ids, isNew: false)
            }
            closeHeld(unit)
            isNew = true
        }
        guard let descriptor = files.openFile(layout.processesFile(of: unit))?.descriptor else { return nil }
        guard let ids = read(descriptor, CgroupFiles.processIDs(parsing:)) else {
            SystemFiles.close(descriptor)
            return nil
        }
        let unitFiles = Files(
            processes: descriptor,
            cpu: files.openFile(layout.cpuFile(of: unit))?.descriptor,
            memory: files.openFile(layout.memoryFile(of: unit))?.descriptor,
            memoryStat: files.openFile(layout.memoryStatFile(of: unit))?.descriptor,
            inputOutput: files.openFile(layout.inputOutputFile(of: unit))?.descriptor
        )
        if held.count < Self.heldUnitLimit { held[unit] = unitFiles }
        return Opened(files: unitFiles, processIDs: ids, isNew: isNew)
    }

    /// In use less the file cache the kernel would reclaim first, as `docker stats` counts it.
    private func memory(of unitFiles: Files, in layout: CgroupLayout) -> UInt64? {
        guard let current = unitFiles.memory.flatMap({ read($0, CgroupFiles.number(parsing:)) }) else { return nil }
        let inactive = unitFiles.memoryStat.flatMap { read($0) { CgroupFiles.inactiveFileBytes(parsing: $0, version: layout.version) } }
        return current - min(inactive ?? 0, current)
    }

    private func rate(_ earlier: UInt64?, _ current: UInt64?, elapsed: Double?) -> Double? {
        guard let earlier, let current, let elapsed else { return nil }
        return CounterIncrease.perSecond(earlier, to: current, seconds: elapsed)
    }

    /// Reads the file from its start into the shared buffer and parses it there, before the next file
    /// is read into the same buffer. Nil when it can't be read, as once its cgroup is removed.
    private func read<Value>(_ descriptor: Int32, _ parse: (ArraySlice<UInt8>) -> Value?) -> Value? {
        guard let count = SystemFiles.readFromStart(descriptor, into: &buffer) else { return nil }
        return parse(buffer[..<count])
    }

    private func closeHeld(_ unit: CgroupUnit) {
        guard let unitFiles = held.removeValue(forKey: unit) else { return }
        close(unitFiles)
    }

    private func close(_ unitFiles: Files) {
        for descriptor in unitFiles.all {
            SystemFiles.close(descriptor)
        }
    }
}
