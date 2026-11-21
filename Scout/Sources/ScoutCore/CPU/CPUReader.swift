import ScoutProtocol

/// Reads how busy the CPU is and its load, keeping the previous reading that use is worked out from.
struct CPUReader {
    let files: SystemFiles
    private var previous: CPUTimes?

    init(files: SystemFiles) {
        self.files = files
    }

    /// - Parameter elapsed: seconds since the previous reading, nil when there's none to compare with.
    mutating func read(elapsed: Double?) -> CPUFigures? {
        guard let times = files.text(at: "/proc/stat").flatMap(CPUTimes.init(parsing:)) else { return nil }
        defer { previous = times }
        let use = elapsed == nil ? nil : previous.flatMap { times.use(since: $0) }
        return CPUFigures(cores: times.cores, use: use, load: files.text(at: "/proc/loadavg").flatMap(Self.loadAverages(parsing:)))
    }

    /// `/proc/loadavg` starts with the 1, 5 and 15-minute averages: `0.52 0.34 0.11 1/983 5977`.
    static func loadAverages(parsing text: String) -> LoadAverages? {
        let fields = text.split(byte: " ").prefix(3).compactMap { Double($0) }
        guard fields.count == 3 else { return nil }
        return LoadAverages(oneMinute: fields[0], fiveMinutes: fields[1], fifteenMinutes: fields[2])
    }
}
