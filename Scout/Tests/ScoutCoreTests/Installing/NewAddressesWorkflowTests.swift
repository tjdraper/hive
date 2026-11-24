import Foundation
@testable import ScoutCore
import ScoutProtocol
import Testing

struct NewAddressesWorkflowTests {
    private static let addresses = [
        EnrollmentCode.Address(host: "hive.tail0000.ts.net", port: 4483),
        EnrollmentCode.Address(host: "100.64.0.9", port: 4484),
    ]

    private let server: TemporaryServer
    private let system: FakeServerSystem

    init() throws {
        server = try TemporaryServer()
        system = FakeServerSystem(layout: InstallLayout(root: server.root.path(percentEncoded: false)))
    }

    /// A server started by `initSystem`, with Scout installed as its service.
    private func installScout(under initSystem: InitSystem) throws {
        let marker = initSystem == .systemd ? "/run/systemd/system/.keep" : "/run/openrc/.keep"
        try server.write(marker, "")
        let tools = initSystem == .systemd ? ["/usr/bin/systemctl"] : ["/sbin/openrc-run", "/sbin/rc-service"]
        for tool in tools {
            try server.write(tool, "")
            chmod(system.layout.onDisk(tool), 0o755)
        }
        try server.write(initSystem.servicePath(in: system.layout), "service")
        system.users[InstallLayout.user] = SystemUser(uid: 500, gid: 500)
    }

    private func replace(with addresses: [EnrollmentCode.Address] = addresses) throws(NewAddressesError) {
        try NewAddressesWorkflow(layout: system.layout, system: system, source: "/proc/self/exe").replace(with: addresses)
    }

    @Test("Scout's user saves the new addresses, then the running service reloads to use them")
    func savesAndReloads() throws {
        // Arrange
        try installScout(under: .systemd)

        // Act
        try replace()

        // Assert
        let saved = try #require(system.savedAddresses.first)
        #expect(try JSONDecoder().decode([EnrollmentCode.Address].self, from: Data(saved.utf8)) == Self.addresses)
        #expect(system.ran == ["systemctl reload hive-scout"])
    }

    @Test("Under OpenRC, the service reloads through rc-service")
    func reloadsUnderOpenRC() throws {
        // Arrange
        try installScout(under: .openRC)

        // Act
        try replace()

        // Assert
        #expect(system.ran == ["rc-service hive-scout reload"])
    }

    @Test("Nothing is saved or reloaded when Scout isn't installed, the addresses aren't usable, or it isn't root")
    func refuses() throws {
        // Arrange
        let tooMany = (1...9).map { EnrollmentCode.Address(host: "hive\($0)", port: 4483) }

        // Act, Assert
        #expect(throws: NewAddressesError.notInstalled) { try replace() }
        try installScout(under: .systemd)
        #expect(throws: NewAddressesError.notAddresses) { try replace(with: []) }
        #expect(throws: NewAddressesError.notAddresses) { try replace(with: tooMany) }
        #expect(throws: NewAddressesError.notAddresses) { try replace(with: [EnrollmentCode.Address(host: "hive", port: 0)]) }
        #expect(throws: NewAddressesError.notAddresses) { try replace(with: [EnrollmentCode.Address(host: "", port: 4483)]) }
        system.isRoot = false
        #expect(throws: NewAddressesError.notRoot) { try replace() }
        #expect(system.savedAddresses.isEmpty)
        #expect(system.commands.isEmpty)
    }

    @Test("When Scout's user can't save them, as before it enrolls, the service isn't reloaded")
    func notSaved() throws {
        // Arrange
        try installScout(under: .systemd)
        system.savesAddresses = false

        // Act, Assert
        #expect(throws: NewAddressesError.notSaved) { try replace() }
        #expect(system.commands.isEmpty)
    }
}
