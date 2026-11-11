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
    private var serverLists: [UUID: ServerList] = [:]
    private var recoveryFiles: [UUID: RecoveryFileCopies] = [:]
    private var liveUpdates: [UUID: Task<Void, Never>] = [:]
    /// Hives first paired since Beekeeper opened, whose setup goes on to their recovery key.
    private var newlyPaired: Set<UUID> = []
    private let file: HiveListFile
    private let keychain = DeviceKeychain()

    init(file: HiveListFile = .standard) {
        self.file = file
        hives = file.load()
        for hive in hives {
            track(hive)
        }
    }

    func hive(_ id: UUID) -> KnownHive? {
        hives.first { $0.id == id }
    }

    func link(for id: UUID) -> HiveLink? {
        links[id]
    }

    func servers(for id: UUID) -> ServerList? {
        serverLists[id]
    }

    func recoveryCopies(for id: UUID) -> RecoveryFileCopies? {
        recoveryFiles[id]
    }

    var hasOfflineHive: Bool {
        hives.contains { links[$0.id]?.status == .offline }
    }

    func refreshAll() async {
        for hive in hives {
            await refresh(hive.id)
        }
    }

    private func refresh(_ id: UUID) async {
        guard let link = links[id] else { return }
        await link.refresh()
        if let name = link.overview?.name { rename(id, to: name) }
        if link.status == .connected { await serverLists[id]?.refresh() }
    }

    private func track(_ hive: KnownHive) {
        let link = HiveLink(hive: hive, keychain: keychain)
        links[hive.id] = link
        let servers = ServerList(link: link)
        serverLists[hive.id] = servers
        let recovery = RecoveryFileCopies(hiveID: hive.id, hiveName: hive.name, link: link)
        recoveryFiles[hive.id] = recovery
        let follower = LiveUpdateFollower(link: link, statuses: servers.statuses, recovery: recovery)
        liveUpdates[hive.id] = Task { await follower.follow() }
    }

    /// True once for a Hive first paired since Beekeeper opened.
    func takeNewlyPaired(_ id: UUID) -> Bool {
        newlyPaired.remove(id) != nil
    }

    /// Keeps the name the Hive gives itself, so the list reads right while it's offline.
    func rename(_ id: UUID, to name: String) {
        guard let index = hives.firstIndex(where: { $0.id == id }), hives[index].name != name else { return }
        hives[index].name = name
        recoveryFiles[id]?.hiveName = name
        file.save(hives)
    }

    /// After the Hive's port changed, so the next request goes to the new one.
    func changePort(of id: UUID, to port: Int) {
        guard let index = hives.firstIndex(where: { $0.id == id }) else { return }
        hives[index].addresses = hives[index].addresses.map { HiveAddress(host: $0.host, port: port) }
        file.save(hives)
        links[id]?.connect(to: hives[index].addresses.first)
    }

    /// Takes a Hive this device is no longer paired with off the list. Its recovery files stay, since
    /// they may be all that's left to bring the Hive back.
    func remove(_ id: UUID) {
        hives.removeAll { $0.id == id }
        links[id] = nil
        serverLists[id] = nil
        recoveryFiles[id] = nil
        liveUpdates.removeValue(forKey: id)?.cancel()
        try? keychain.delete(hiveID: id)
        file.save(hives)
    }

    #if os(macOS)
    var hasHiveOnThisMac: Bool {
        hives.contains(where: \.isOnThisMac)
    }

    /// After this Mac's Hive took a new identity, which unpaired this device and restarts Hive: pairs again
    /// once Hive is back. Hive turns pairing away until it has restarted, so the pin is always the new key's.
    func pairAgainAfterNewIdentity(_ id: UUID) {
        guard let link = links[id] else { return }
        link.startPairingAgain()
        Task {
            let deadline = ContinuousClock.now + Self.restartAllowance
            while true {
                do {
                    _ = try await pairWithThisMac()
                    return
                } catch where Self.isRestarting(error) && ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .seconds(2))
                } catch {
                    Self.logger.error("Couldn't pair again after a new identity: \(String(describing: error), privacy: .public)")
                    link.connect(to: hive(id)?.addresses.first)
                    return
                }
            }
        }
    }

    /// launchd waits up to 10 seconds before starting a daemon again, and Hive waits for its run to stop.
    private static let restartAllowance = Duration.seconds(60)

    private static func isRestarting(_ error: any Error) -> Bool {
        switch error {
        case LocalPairingError.unreachable, LocalPairingError.refused(.hiveUnavailable): true
        default: false
        }
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
            track(hive)
            newlyPaired.insert(hive.id)
        }
        file.save(hives)
        Self.logger.notice("Saved this Mac's Hive in the list")

        await refresh(pairing.hiveID)
        return pairing.hiveID
    }
    #endif
}
