import GRDB

/// The store's migrations for Scouts, registered in order with the rest in `HiveDatabaseMigrator`.
extension HiveDatabaseMigrator {
    static func addScouts(_ database: Database) throws {
        try database.create(table: "scout") { table in
            table.primaryKey("id", .blob)
            // One for each server. Removing the server removes its Scout.
            table.column("serverID", .blob).notNull().unique().references("server", onDelete: .cascade)
            // The X9.63 form of its P-256 key.
            table.column("publicKey", .blob).notNull().unique()
            table.column("enrolledAt", .datetime).notNull()
            table.column("lastSeenAt", .datetime)
            table.column("version", .text)
            table.column("platform", .text)
        }
    }

    static func addServerMetrics(_ database: Database) throws {
        try database.alter(table: "server") { table in
            // Kept apart from its Scout, which a recovery file never holds, so a restored Hive knows
            // which servers' Scouts have to enroll again.
            table.add(column: "hasMetrics", .boolean).notNull().defaults(to: false)
        }
        try database.execute(sql: "UPDATE server SET hasMetrics = 1 WHERE id IN (SELECT serverID FROM scout)")
        try database.alter(table: "scout") { table in
            table.add(column: "protocolVersion", .integer)
        }
    }
}
