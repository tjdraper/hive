/// One reading of a server's figures, taken on a 10-second mark of the server's clock.
///
/// Figures that are rates, such as CPU shares and bytes per second, come from the difference between
/// two readings, so they're missing from the first sample after Scout starts or the server restarts.
public struct MetricsSample: Codable, Hashable, Sendable {
    /// Seconds since 1970 on the server's clock, which may differ from Hive's.
    public var takenAt: Int64
    public var server: ServerFacts
    public var cpu: CPUFigures?
    public var memory: MemoryFigures?
    /// Missing where the kernel has no `/proc/pressure`, and from the first sample.
    public var pressure: PressureFigures?
    public var filesystems: [FilesystemFigures]
    public var disks: [DiskFigures]
    public var networkInterfaces: [NetworkInterfaceFigures]
    /// Missing where `/proc` hides other users' processes, which ``ServerFacts/processesHidden`` reports.
    public var processes: ProcessFigures?
    /// Missing where Scout can't read cgroups, and from a Scout older than protocol version 2.
    public var containers: CgroupFigures?
    public var services: CgroupFigures?

    public init(
        takenAt: Int64,
        server: ServerFacts,
        cpu: CPUFigures?,
        memory: MemoryFigures?,
        pressure: PressureFigures?,
        filesystems: [FilesystemFigures],
        disks: [DiskFigures],
        networkInterfaces: [NetworkInterfaceFigures],
        processes: ProcessFigures?,
        containers: CgroupFigures? = nil,
        services: CgroupFigures? = nil
    ) {
        self.takenAt = takenAt
        self.server = server
        self.cpu = cpu
        self.memory = memory
        self.pressure = pressure
        self.filesystems = filesystems
        self.disks = disks
        self.networkInterfaces = networkInterfaces
        self.processes = processes
        self.containers = containers
        self.services = services
    }
}
