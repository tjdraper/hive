/// User names by number, from `/etc/passwd`, read again only when it changes. A user that only a
/// directory service such as LDAP knows is shown by number.
struct UserNames {
    let files: SystemFiles
    private var names: [UInt32: String] = [:]
    private var readAt: Int64?

    init(files: SystemFiles) {
        self.files = files
    }

    func name(of id: UInt32) -> String {
        names[id] ?? String(id)
    }

    mutating func refresh() {
        let modified = files.modificationTime(at: "/etc/passwd")
        guard modified != readAt else { return }
        readAt = modified
        names = files.text(at: "/etc/passwd").map(Self.names(parsing:)) ?? [:]
    }

    /// Lines of `name:password:id:...`. The first name for an ID wins, as it does for the system.
    static func names(parsing text: String) -> [UInt32: String] {
        var names: [UInt32: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count >= 3, !fields[0].isEmpty, let id = UInt32(fields[2]), names[id] == nil else { continue }
            names[id] = String(fields[0])
        }
        return names
    }
}
