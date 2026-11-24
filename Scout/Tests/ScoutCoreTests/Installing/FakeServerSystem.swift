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
    /// Answers for programs, by name, in place of succeeding.
    var answers: [String: CommandResult] = [:]
    var enrollSucceeds = true
    var enrolledCodes: [String] = []
    var savesAddresses = true
    /// The JSON each `addresses` was given.
    var savedAddresses: [String] = []

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

    func groupExists(_ name: String) -> Bool {
        groups.contains(name)
    }

    func run(_ arguments: [String]) -> CommandResult {
        commands.append(arguments)
        let program = URL(filePath: arguments[0]).lastPathComponent
        if let answer = answers[program] { return answer }
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
        default:
            break
        }
        return CommandResult(status: 0, output: "")
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
