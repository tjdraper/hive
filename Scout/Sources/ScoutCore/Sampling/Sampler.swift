import ScoutProtocol

/// Takes a server's samples. It keeps the previous readings that rates are worked out from, so one
/// sampler serves a run of samples.
public struct Sampler {
    private let files: SystemFiles
    private let eventLoop: ScoutEventLoop
    private let serverFacts: ServerFactsReader
    private let filesystems: FilesystemReader
    private var cpu: CPUReader
    private var memory: MemoryReader
    private var pressure: PressureReader
    private var disks: DiskReader
    private var network: NetworkReader
    private var processes: ProcessReader
    private let cgroups: CgroupReader
    private var previousTime: ReadingTime?

    public init(files: SystemFiles = SystemFiles(), on eventLoop: ScoutEventLoop = .shared) {
        self.init(files: files, filesystemSpace: FilesystemSpaceReader(files: files), on: eventLoop)
    }

    init(files: SystemFiles, filesystemSpace: FilesystemSpaceReader, on eventLoop: ScoutEventLoop) {
        self.files = files
        self.eventLoop = eventLoop
        serverFacts = ServerFactsReader(files: files)
        filesystems = FilesystemReader(space: filesystemSpace)
        cpu = CPUReader(files: files)
        memory = MemoryReader(files: files)
        pressure = PressureReader(files: files)
        disks = DiskReader(files: files)
        network = NetworkReader(files: files)
        processes = ProcessReader(files: files)
        cgroups = CgroupReader(files: files)
    }

    /// - Parameter takenAt: the sample's mark, in seconds since 1970.
    public mutating func sample(takenAt: Int64) async -> MetricsSample {
        let time = ReadingTime(files: files)
        let elapsed = time?.seconds(since: previousTime)
        previousTime = time

        let mounts = files.text(at: "/proc/self/mountinfo").map(Mount.all(parsing:)) ?? []
        let processesHidden = mounts.processesHidden
        // Before processes, which are grouped by the unit each is in.
        let units = cgroups.read(elapsed: elapsed)
        let processReading = processesHidden ? nil : processes.read(at: time, elapsed: elapsed, units: units?.unitOfProcess ?? [:])
        let counters = (
            cpu: cpu.read(elapsed: elapsed),
            memory: memory.read(elapsed: elapsed),
            pressure: pressure.read(elapsed: elapsed),
            disks: disks.read(elapsed: elapsed),
            network: network.read(elapsed: elapsed)
        )
        // Last, since a filesystem that doesn't answer holds the sample up until it times out.
        let filesystems = await filesystems.read(mounts: mounts, on: eventLoop)

        return MetricsSample(
            takenAt: takenAt,
            server: serverFacts.read(processesHidden: processesHidden),
            cpu: counters.cpu,
            memory: counters.memory,
            pressure: counters.pressure,
            filesystems: filesystems,
            disks: counters.disks,
            networkInterfaces: counters.network,
            processes: processReading?.figures,
            containers: units.map { CgroupReader.figures(of: $0.containers, commands: processReading?.containerCommands ?? [:]) },
            services: units.map { CgroupReader.figures(of: $0.services) }
        )
    }
}
