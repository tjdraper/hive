import Foundation
import GRDB
import HiveKit

/// Opens a warning when a device's build is 14 days, then 3 days, from expiring (§16). Each is
/// recorded on the device with opening it, so it goes out once for each build, and a new build
/// reported at sign-in starts them over.
struct BuildExpiryCheck: Sendable {
    let database: HiveDatabase

    func openDueWarnings(at date: Date) throws -> AlertStore.Applied {
        try database.writer.write { database in
            let isOn = try Bool.fetchOne(database, sql: "SELECT sendsBuildExpiryWarnings FROM hive") ?? true
            guard isOn else { return AlertStore.Applied() }

            var changes: [AlertStore.Change] = []
            for var device in try PairedDevice.filter(Column("build") != nil).fetchAll(database) {
                guard let build = device.build,
                      let expiresAt = build.expiresAt,
                      let due = BuildExpiryWarning.due(expiresAt: expiresAt, at: date),
                      device.buildWarning.map({ $0 < due }) ?? true
                else { continue }
                device.buildWarning = due
                try device.update(database)
                changes.append(.open(.buildExpiring(deviceID: device.id, deviceName: device.name, build: build, warning: due)))
            }
            return try AlertStore.apply(changes, at: date, in: database)
        }
    }
}
