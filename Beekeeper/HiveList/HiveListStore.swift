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
    private let browser = LocalHiveBrowser()

    init(file: HiveListFile = .standard) {
        self.file = file
        hives = file.load()
        for hive in hives {
            track(hive)
        }
        browser.onChange = { [weak self] in self?.useDiscoveredAddresses() }
        if hives.contains(where: { !$0.isOnThisMac }) { browser.start() }
    }

    /// Looks for Hives on the local network, such as while pairing with one. Not before, since the first
    /// time it asks for local network access, which a Mac that only manages its own Hive never needs.
    func discoverLocalHives() {
        browser.start()
    }

    /// Beekeeper on the Hive's Mac reaches it on `127.0.0.1`, and ignores where else it's found.
    private func useDiscoveredAddresses() {
        for hive in hives where !hive.isOnThisMac {
            guard let link = links[hive.id] else { continue }
            let addresses = browser.addresses(for: hive.id)
            link.useDiscovered(addresses)
            if !addresses.isEmpty, link.status == .offline {
                Task { await refresh(hive.id) }
            }
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
        if let overview = link.overview {
            rename(id, to: overview.name)
            follow(id, to: overview.addresses)
        }
        if link.status == .connected { await serverLists[id]?.refresh() }
    }

    private func track(_ hive: KnownHive) {
        let link = HiveLink(hive: hive, keychain: keychain)
        if !hive.isOnThisMac { link.useDiscovered(browser.addresses(for: hive.id)) }
        links[hive.id] = link
        let servers = ServerList(link: link)
        serverLists[hive.id] = servers
        let recovery = RecoveryFileCopies(hiveID: hive.id, hiveName: hive.name, link: link)
        recoveryFiles[hive.id] = recovery
        let follower = LiveUpdateFollower(link: link, statuses: servers.statuses, recovery: recovery) { [weak self] addresses in
            self?.follow(hive.id, to: addresses)
        }
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

    /// Keeps up with the Hive's port and address options, whichever device changed them, so the next
    /// request goes where the Hive is now. A Hive with no address options leaves the ones this device
    /// has, since it's reaching the Hive through them.
    func follow(_ id: UUID, to addresses: HiveAddresses) {
        guard let index = hives.firstIndex(where: { $0.id == id }) else { return }
        let new = hives[index].isOnThisMac ? [HiveAddress(host: "127.0.0.1", port: addresses.port)] : addresses.options
        guard !new.isEmpty, new != hives[index].addresses else { return }
        hives[index].addresses = new
        file.save(hives)
        links[id]?.connect(to: new)
        Self.logger.notice("Followed a Hive to new addresses")
    }

    /// Pairs with a Hive through a pairing code from a device already paired with it, and returns its ID.
    /// Pairing again with a Hive already in the list, such as one whose identity changed, replaces it.
    func pairWithCode(_ code: PairingCode, deviceName: String) async throws -> UUID {
        let result = try await CodePairingWorkflow(keychain: keychain)
            .pair(code, deviceName: deviceName, discovered: browser.addresses(for: code.hiveID))
        let addresses = result.addresses.options.isEmpty ? code.addresses : result.addresses.options

        if let index = hives.firstIndex(where: { $0.id == result.hiveID }) {
            hives[index].name = result.hiveName
            if !hives[index].isOnThisMac { hives[index].addresses = addresses }
            links[result.hiveID]?.connect(to: hives[index].addresses)
        } else {
            let hive = KnownHive(id: result.hiveID, name: result.hiveName, addresses: addresses, isOnThisMac: false)
            hives.append(hive)
            track(hive)
            newlyPaired.insert(hive.id)
        }
        file.save(hives)
        Self.logger.notice("Saved a Hive paired with a code in the list")

        await refresh(result.hiveID)
        return result.hiveID
    }

    /// Takes a Hive this device is no longer paired with off the list. Its recovery files stay, since
    /// they may be all that's left to bring the Hive back.
    func remove(_ id: UUID) {
        hives.removeAll { $0.id == id }
        untrack(id)
        try? keychain.delete(hiveID: id)
        file.save(hives)
    }

    /// Revokes this device on the Hive when it can, so the Hive's device list doesn't keep a device that
    /// no longer has a key, then takes the Hive off the list. Returns whether the Hive revoked it.
    @discardableResult
    func removeRevokingThisDevice(_ id: UUID) async -> Bool {
        var revoked = false
        if let link = links[id], link.status == .connected, let deviceID = link.deviceID {
            do {
                try await link.perform { try await $0.delete(HiveEndpoint.device(deviceID)) }
                revoked = true
            } catch {
                let kind = String(describing: type(of: error))
                Self.logger.error("Couldn't revoke this device before removing a Hive: \(kind, privacy: .public)")
            }
        }
        remove(id)
        Self.logger.notice("Removed a Hive from the list, revoked on the Hive: \(revoked, privacy: .public)")
        return revoked
    }

    private func untrack(_ id: UUID) {
        links[id] = nil
        serverLists[id] = nil
        recoveryFiles[id] = nil
        liveUpdates.removeValue(forKey: id)?.cancel()
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
                    link.connect(to: hive(id)?.addresses ?? [])
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

    /// After this Mac's Hive was restored from a recovery file: it restarts as the restored Hive, which
    /// kept this device, so Beekeeper's key for it is filed under the restored Hive's ID. An entry this
    /// device had for the restored Hive pinned the old Mac's identity key, which is no use now, so the
    /// restored Hive takes its place, and signs in once Hive is back. False when this device's key
    /// couldn't be kept, which leaves the list as it was.
    @discardableResult
    func adoptRestoredHive(_ id: UUID, as outcome: RestoreOutcome) -> Bool {
        guard let index = hives.firstIndex(where: { $0.id == id }) else { return false }
        // The restored Hive's port, which may not be the one the new Hive started on.
        let address = HiveAddress(host: "127.0.0.1", port: outcome.port)
        let restored = KnownHive(id: outcome.hiveID, name: outcome.hiveName, addresses: [address], isOnThisMac: true)
        do {
            guard let credential = try keychain.credential(for: id) else { return false }
            try keychain.save(DeviceCredential(
                hiveID: restored.id,
                deviceID: credential.deviceID,
                pin: credential.pin,
                keyData: credential.keyData,
                confirmationKeyData: credential.confirmationKeyData
            ))
            try keychain.delete(hiveID: id)
        } catch {
            Self.logger.error("Couldn't keep this device's key for the restored Hive: \(String(describing: error), privacy: .public)")
            return false
        }

        untrack(id)
        untrack(restored.id)
        hives.removeAll { $0.id == id || $0.id == restored.id }
        hives.insert(restored, at: min(index, hives.count))
        track(restored)
        file.save(hives)
        Self.logger.notice("Saved the restored Hive in the list")
        let link = links[restored.id]
        let servers = serverLists[restored.id]
        link?.expectRestart()
        Task {
            await link?.reconnectAfterRestart()
            if link?.status == .connected { await servers?.refresh() }
        }
        return true
    }

    /// Pairs with this Mac's Hive, or again with it after this device was revoked, and returns its ID.
    func pairWithThisMac() async throws -> UUID {
        let pairing = try await LocalPairingWorkflow(keychain: keychain).pair()
        let address = HiveAddress(host: "127.0.0.1", port: pairing.port)

        if let index = hives.firstIndex(where: { $0.id == pairing.hiveID }) {
            hives[index].addresses = [address]
            links[pairing.hiveID]?.connect(to: [address])
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
