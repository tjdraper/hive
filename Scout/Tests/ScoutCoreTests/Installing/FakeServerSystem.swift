import Foundation
@testable import ScoutCore

/// A server's users and programs, for installing into a temporary root: records what it's asked to
/// run, and keeps users and groups the way `useradd` and its kin would.
final class FakeServerSystem: ServerSystem {
    let layout: InstallLayout
    var isRoot = true
    var users: [String: SystemUser] = ["deploy": SystemUser(uid: 1000, gid: 1000)]
    var groups: Set<String> = ["deploy"]
    var commands: [[String]] = []
    /// Answers for programs, by name, or by name and first argument, such as `launchctl print`, in
    /// place of succeeding.
    var answers: [String: CommandResult] = [:]
    var enrollSucceeds = true
    var enrolledCodes: [String] = []
    var savesAddresses = true
    /// The JSON each `addresses` was given.
    var savedAddresses: [String] = []
    /// IDs of users and groups the fake doesn't otherwise keep, such as macOS's own.
    var takenIDs: Set<UInt32> = []
    /// As this machine sees them.
    var foldersOthersCanChange: Set<String> = []

    init(layout: InstallLayout) {
        self.layout = layout
    }

    /// The programs run, by name, with their arguments.
    var ran: [String] {
        commands.map { ([URL(filePath: $0[0]).lastPathComponent] + $0.dropFirst()).joined(separator: " ") }
    }

    func user(named name: String) -> SystemUser? {
        users[name]
    }

    func groupID(named name: String) -> gid_t? {
        groups.contains(name) ? 500 : nil
    }

    func idInUse(_ id: UInt32) -> Bool {
        takenIDs.contains(id) || users.values.contains { $0.uid == id || $0.gid == id }
    }

    func onlyRootCanChange(folder path: String) -> Bool {
        !foldersOthersCanChange.contains(path)
    }

    func run(_ arguments: [String]) -> CommandResult {
        commands.append(arguments)
        let program = URL(filePath: arguments[0]).lastPathComponent
        if let answer = answers["\(program) \(arguments.dropFirst().first ?? "")"] ?? answers[program] { return answer }
        let name = arguments.last ?? ""
        switch program {
        case "useradd":
            users[name] = SystemUser(uid: 500, gid: 500)
            if arguments.contains("--user-group") { groups.insert(name) }
        case "adduser":
            users[name] = SystemUser(uid: 500, gid: 500)
        case "addgroup":
            groups.insert(name)
        case "userdel", "deluser":
            users[name] = nil
        case "groupdel", "delgroup":
            groups.remove(name)
        case "dscl":
            recordDirectoryChange(arguments)
        default:
            break
        }
        return CommandResult(status: 0, output: "")
    }

    /// `dscl . -create /Users/<name> UniqueID <id>` and the like, keeping a Mac's users and groups.
    private func recordDirectoryChange(_ arguments: [String]) {
        guard arguments.count >= 4 else { return }
        let record = arguments[3].split(separator: "/").map(String.init)
        guard record.count == 2 else { return }
        let (kind, name) = (record[0], record[1])
        switch (arguments[2], kind) {
        case ("-create", "Groups"):
            groups.insert(name)
        case ("-create", "Users"):
            var user = users[name] ?? SystemUser(uid: 0, gid: 0)
            if arguments.count == 6, let id = UInt32(arguments[5]) {
                if arguments[4] == "UniqueID" { user = SystemUser(uid: id, gid: user.gid) }
                if arguments[4] == "PrimaryGroupID" { user = SystemUser(uid: user.uid, gid: id) }
            }
            users[name] = user
        case ("-delete", "Users"):
            users[name] = nil
        case ("-delete", "Groups"):
            groups.remove(name)
        default:
            break
        }
    }

    func enroll(code: String, binary _: String, stateDirectory: String) -> Bool {
        enrolledCodes.append(code)
        guard enrollSucceeds else { return false }
        let file = layout.onDisk(stateDirectory) + "/enrollment.json"
        return FileManager.default.createFile(atPath: file, contents: Data("{}".utf8))
    }

    func replaceAddresses(json: [UInt8], binary _: String, stateDirectory _: String) -> Bool {
        savedAddresses.append(String(bytes: json, encoding: .utf8) ?? "")
        return savesAddresses
    }

    func changeOwner(of _: Int32, to _: SystemUser) -> Bool {
        true
    }
}
