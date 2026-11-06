import Foundation
import HiveKit
import Observation
import os

/// The Hives this device has paired with, kept across launches, each with its live connection.
@Observable
final class HiveListStore {
    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "HiveList")

    private(set) var hives: [KnownHive]
    private var links: [UUID: HiveLink] = [:]
    private let file: HiveListFile
    private let keychain = DeviceKeychain()

    init(file: HiveListFile = .standard) {
        self.file = file
        hives = file.load()
        for hive in hives {
            links[hive.id] = HiveLink(hive: hive, keychain: keychain)
        }
    }

    func hive(_ id: UUID) -> KnownHive? {
        hives.first { $0.id == id }
    }

    func link(for id: UUID) -> HiveLink? {
        links[id]
    }

    func refreshAll() async {
        for hive in hives {
            guard let link = links[hive.id] else { continue }
            await link.refresh()
            if let name = link.overview?.name { rename(hive.id, to: name) }
        }
    }

    /// Keeps the name the Hive gives itself, so the list reads right while it's offline.
    func rename(_ id: UUID, to name: String) {
        guard let index = hives.firstIndex(where: { $0.id == id }), hives[index].name != name else { return }
        hives[index].name = name
        file.save(hives)
    }

    /// After the Hive's port changed, so the next request goes to the new one.
    func changePort(of id: UUID, to port: Int) {
        guard let index = hives.firstIndex(where: { $0.id == id }) else { return }
        hives[index].addresses = hives[index].addresses.map { HiveAddress(host: $0.host, port: port) }
        file.save(hives)
        links[id]?.connect(to: hives[index].addresses.first)
    }

    /// Takes a Hive this device is no longer paired with off the list.
    func remove(_ id: UUID) {
        hives.removeAll { $0.id == id }
        links[id] = nil
        try? keychain.delete(hiveID: id)
        file.save(hives)
    }

    #if os(macOS)
    var hasHiveOnThisMac: Bool {
        hives.contains(where: \.isOnThisMac)
    }

    /// Pairs with this Mac's Hive, or again with it after this device was revoked, and returns its ID.
    func pairWithThisMac() async throws -> UUID {
        let pairing = try await LocalPairingWorkflow(keychain: keychain).pair()
        let address = HiveAddress(host: "127.0.0.1", port: pairing.port)

        if let index = hives.firstIndex(where: { $0.id == pairing.hiveID }) {
            hives[index].addresses = [address]
            links[pairing.hiveID]?.connect(to: address)
        } else {
            let hive = KnownHive(id: pairing.hiveID, name: "This Mac's Hive", addresses: [address], isOnThisMac: true)
            hives.append(hive)
            links[hive.id] = HiveLink(hive: hive, keychain: keychain)
        }
        file.save(hives)
        Self.logger.notice("Added this Mac's Hive to the list")

        if let link = links[pairing.hiveID] {
            await link.refresh()
            if let name = link.overview?.name { rename(pairing.hiveID, to: name) }
        }
        return pairing.hiveID
    }
    #endif
}
