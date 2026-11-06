import Foundation
import HiveKit
import os

/// What the settings workflow needs from `ListenerCoordinator`, so tests can stand in for it.
protocol ListenerControl: Sendable {
    func apply(_ target: ListenTarget) async throws
    func listeningHosts() async -> [String]
}

enum SettingsChangeError: Error, Equatable {
    case refused(SettingsProblem)
}

/// Changing the Hive's name and where it listens. A listening change takes effect before it's saved, so
/// a port that's taken is turned down with nothing changed, and nothing waits for the daemon to restart.
struct HiveSettingsWorkflow: Sendable {
    static let ports = 1024 ... 65535

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Settings")

    let store: HiveSettingsStore
    let listeners: any ListenerControl
    let now: @Sendable () -> Date

    func state() async throws -> HiveSettingsState {
        HiveSettingsState(
            settings: try store.settings(),
            interfaces: NetworkInterfaceList.current(),
            listeningOn: await listeners.listeningHosts()
        )
    }

    func change(to requested: HiveSettings, by deviceID: UUID) async throws -> HiveSettingsState {
        let new = try Self.validated(requested)
        let old = try store.settings()
        guard new != old else { return try await state() }

        let listeningChanged = new.listenTarget != old.listenTarget
        if listeningChanged {
            do {
                try await listeners.apply(new.listenTarget)
            } catch ListenerCoordinatorError.loopbackUnavailable {
                Self.logger.error("Refused a settings change: port unavailable")
                throw SettingsChangeError.refused(.portUnavailable)
            }
        }

        do {
            try store.save(new, replacing: old, by: deviceID, at: now())
        } catch {
            if listeningChanged { try? await listeners.apply(old.listenTarget) }
            throw error
        }
        Self.logger.notice("Changed the settings")
        return try await state()
    }

    static func validated(_ requested: HiveSettings) throws -> HiveSettings {
        guard let name = DisplayName.validated(requested.name) else { throw SettingsChangeError.refused(.invalidName) }
        guard ports.contains(requested.port) else { throw SettingsChangeError.refused(.invalidPort) }

        let networkAccess: NetworkAccess
        switch requested.networkAccess {
        case .address(let address):
            guard let reachable = ListenAddress.reachable(address) else { throw SettingsChangeError.refused(.invalidAddress) }
            networkAccess = .address(reachable)
        case .thisMacOnly, .allAddresses:
            networkAccess = requested.networkAccess
        }
        return HiveSettings(name: name, networkAccess: networkAccess, port: requested.port)
    }
}
