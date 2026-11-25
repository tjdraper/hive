/// Where the kernel keeps cgroups' files. Cgroup v2 has one hierarchy for every controller; v1 has one
/// for each, and a server can mix them, with the controllers in v1 and only systemd's own tracking in
/// v2, which counts as v1 since that's where the figures are.
enum CgroupVersion: Equatable {
    case version1
    case version2
}

/// A Docker container or systemd service's cgroup, by its path within a hierarchy, such as
/// `system.slice/cron.service`.
struct CgroupUnit: Hashable {
    enum Kind: Hashable {
        case container
        case service
    }

    let kind: Kind
    /// A container's full ID, or a service's unit name.
    let name: String
    let path: String
}

struct CgroupLayout: Equatable {
    static let root = "/sys/fs/cgroup"

    let version: CgroupVersion
    /// Where units are listed and their processes read: v1's systemd hierarchy, which has every
    /// service whether or not systemd accounts for it, or `cpuacct` on a server without systemd.
    let listingRoot: String

    /// Nil where the server has no cgroups Scout can read.
    static func detect(in files: SystemFiles) -> CgroupLayout? {
        if files.modificationTime(at: "\(root)/cgroup.controllers") != nil {
            return CgroupLayout(version: .version2, listingRoot: root)
        }
        for hierarchy in ["systemd", "cpuacct"] where files.modificationTime(at: "\(root)/\(hierarchy)") != nil {
            return CgroupLayout(version: .version1, listingRoot: "\(root)/\(hierarchy)")
        }
        return nil
    }

    /// The folders units are found in, under `listingRoot`: systemd's driver puts Docker's containers
    /// beside the services in `system.slice` and Podman's in `machine.slice`, and Docker's own driver
    /// puts them in `docker`.
    static let unitFolders = ["system.slice", "machine.slice", "docker"]

    /// The unit a folder entry is, or nil for anything else, such as a mount or socket. A slice in
    /// `system.slice` holds services made from one template, such as `getty@tty1.service`, and is
    /// read for them in turn.
    static func unit(named entry: String, in folder: String) -> CgroupUnit? {
        let path = "\(folder)/\(entry)"
        if folder == "docker" {
            return isContainerID(entry) ? CgroupUnit(kind: .container, name: entry, path: path) : nil
        }
        for prefix in ["docker-", "libpod-"] where entry.hasPrefix(prefix) && entry.hasSuffix(".scope") {
            let id = String(entry.dropFirst(prefix.count).dropLast(".scope".count))
            return isContainerID(id) ? CgroupUnit(kind: .container, name: id, path: path) : nil
        }
        if folder.hasPrefix("system.slice"), entry.hasSuffix(".service") {
            return CgroupUnit(kind: .service, name: entry, path: path)
        }
        return nil
    }

    static func isContainerID(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48 ... 57).contains($0) || (97 ... 102).contains($0) }
    }

    func processesFile(of unit: CgroupUnit) -> String {
        "\(listingRoot)/\(unit.path)/cgroup.procs"
    }

    func cpuFile(of unit: CgroupUnit) -> String {
        version == .version2 ? "\(Self.root)/\(unit.path)/cpu.stat" : "\(Self.root)/cpuacct/\(unit.path)/cpuacct.usage"
    }

    func memoryFile(of unit: CgroupUnit) -> String {
        version == .version2 ? "\(Self.root)/\(unit.path)/memory.current" : "\(Self.root)/memory/\(unit.path)/memory.usage_in_bytes"
    }

    func memoryStatFile(of unit: CgroupUnit) -> String {
        version == .version2 ? "\(Self.root)/\(unit.path)/memory.stat" : "\(Self.root)/memory/\(unit.path)/memory.stat"
    }

    func inputOutputFile(of unit: CgroupUnit) -> String {
        version == .version2
            ? "\(Self.root)/\(unit.path)/io.stat"
            : "\(Self.root)/blkio/\(unit.path)/blkio.throttle.io_service_bytes_recursive"
    }
}
