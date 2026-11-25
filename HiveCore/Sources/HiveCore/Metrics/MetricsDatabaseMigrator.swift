import GRDB

/// Every change to the metrics database's shape, in order. A migration that has shipped is never
/// edited, so each one lists its own columns rather than reading `MetricsTables`, which changes with
/// the next migration. A test checks the two agree.
enum MetricsDatabaseMigrator {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("Create the metrics tables", migrate: createMetricsTables)
        migrator.registerMigration("Keep containers and services", migrate: createCgroupTables)
        migrator.registerMigration("Keep other users' processes", migrate: addOtherUsersProcesses)
        return migrator
    }

    private struct FigureColumn {
        let name: String
        let type: Database.ColumnType
        let kept: MetricsKept

        init(_ name: String, _ type: Database.ColumnType, _ kept: MetricsKept) {
            self.name = name
            self.type = type
            self.kept = kept
        }
    }

    private static func createMetricsTables(_ database: Database) throws {
        try createServersAndNames(database)
        try createServerFigureTables(database)
        try createNamedFigureTables(database)
        try createProcessTables(database)
    }

    private static func createServersAndNames(_ database: Database) throws {
        try database.create(table: "metricsServer") { table in
            table.autoIncrementedPrimaryKey("id")
            // Not a reference to Hive's store, which is another database. Hive removes a server's
            // metrics with it, and the hourly pass removes any it missed.
            table.column("serverID", .blob).notNull().unique()
            // Hive's clock, when this server last sent anything, kept or not.
            table.column("lastReportAt", .datetime)
            // The server's clock less Hive's, in seconds, from when the last request was sent.
            table.column("clockOffsetSeconds", .integer)
            // The newest sample kept, on the server's clock, and what it said about the server.
            table.column("lastSampleAt", .integer)
            table.column("uptimeSeconds", .double)
            table.column("scoutVersion", .text)
            table.column("distribution", .text)
            table.column("kernel", .text)
            table.column("processesHidden", .boolean)
            // A `ScoutRefusal.Reason`, kept until something is kept again.
            table.column("lastRefusal", .text)
            table.column("lastRefusedAt", .datetime)
        }

        try database.create(table: "metricsName") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("serverKey", .integer).notNull().references("metricsServer", onDelete: .cascade)
            table.column("kind", .text).notNull()
            table.column("name", .text).notNull()
            // Hive's clock, for limiting how many new names a server brings in a day.
            table.column("firstSeenAt", .datetime).notNull()
            // A filesystem's, as last reported.
            table.column("device", .text)
            table.column("type", .text)
            table.uniqueKey(["serverKey", "kind", "name"])
        }
        try database.create(index: "metricsName_on_firstSeenAt", on: "metricsName", columns: ["serverKey", "firstSeenAt"])
    }

    private static func createServerFigureTables(_ database: Database) throws {
        try createFigureTables("server", keyedBy: "metricsServer", columns: [
            FigureColumn("cores", .integer, .average),
            FigureColumn("cpuUser", .double, .averageAndHighest),
            FigureColumn("cpuSystem", .double, .averageAndHighest),
            FigureColumn("cpuIOWait", .double, .averageAndHighest),
            FigureColumn("cpuSteal", .double, .averageAndHighest),
            FigureColumn("loadOneMinute", .double, .averageAndHighest),
            FigureColumn("loadFiveMinutes", .double, .averageAndHighest),
            FigureColumn("loadFifteenMinutes", .double, .averageAndHighest),
            FigureColumn("memoryTotal", .integer, .average),
            FigureColumn("memoryAvailable", .integer, .averageHighestAndLowest),
            FigureColumn("memoryCache", .integer, .averageAndHighest),
            FigureColumn("swapTotal", .integer, .average),
            FigureColumn("swapUsed", .integer, .averageAndHighest),
            FigureColumn("swapInPages", .double, .averageAndHighest),
            FigureColumn("swapOutPages", .double, .averageAndHighest),
            FigureColumn("pressureCPUSome", .double, .averageAndHighest),
            FigureColumn("pressureCPUFull", .double, .averageAndHighest),
            FigureColumn("pressureMemorySome", .double, .averageAndHighest),
            FigureColumn("pressureMemoryFull", .double, .averageAndHighest),
            FigureColumn("pressureIOSome", .double, .averageAndHighest),
            FigureColumn("pressureIOFull", .double, .averageAndHighest),
            FigureColumn("processes", .integer, .averageAndHighest),
            FigureColumn("zombies", .integer, .averageAndHighest),
        ], in: database)
    }

    private static func createNamedFigureTables(_ database: Database) throws {
        try createFigureTables("filesystem", keyedBy: "metricsName", columns: [
            FigureColumn("size", .integer, .average),
            FigureColumn("used", .integer, .averageAndHighest),
            FigureColumn("available", .integer, .averageHighestAndLowest),
            FigureColumn("inodesUsed", .integer, .averageAndHighest),
            FigureColumn("inodesFree", .integer, .averageHighestAndLowest),
        ], in: database)

        try createFigureTables("disk", keyedBy: "metricsName", columns: [
            FigureColumn("readBytes", .double, .averageAndHighest),
            FigureColumn("writtenBytes", .double, .averageAndHighest),
            FigureColumn("reads", .double, .averageAndHighest),
            FigureColumn("writes", .double, .averageAndHighest),
            FigureColumn("busy", .double, .averageAndHighest),
        ], in: database)

        try createFigureTables("networkInterface", keyedBy: "metricsName", columns: [
            FigureColumn("receivedBytes", .double, .averageAndHighest),
            FigureColumn("sentBytes", .double, .averageAndHighest),
            FigureColumn("receiveErrors", .double, .averageAndHighest),
            FigureColumn("sendErrors", .double, .averageAndHighest),
            FigureColumn("receiveDrops", .double, .averageAndHighest),
            FigureColumn("sendDrops", .double, .averageAndHighest),
        ], in: database)
    }

    private static func createProcessTables(_ database: Database) throws {
        // Each sample's process groups as compressed JSON, since they're only ever read whole for a moment.
        try database.create(table: "processTenSeconds") { table in
            table.column("serverKey", .integer).notNull().references("metricsServer", onDelete: .cascade)
            table.column("startsAt", .integer).notNull()
            table.column("groups", .blob).notNull()
            table.primaryKey(["serverKey", "startsAt"])
        }
        try database.create(table: "processHour") { table in
            table.column("serverKey", .integer).notNull().references("metricsServer", onDelete: .cascade)
            table.column("startsAt", .integer).notNull()
            // How many samples it was made from, so one that arrives late makes it again.
            table.column("sampleCount", .integer).notNull()
            table.column("groups", .blob).notNull()
            table.primaryKey(["serverKey", "startsAt"])
        }
    }

    private static func createCgroupTables(_ database: Database) throws {
        // Each sample's containers and services as compressed JSON, read whole for a moment or a range.
        try database.create(table: "cgroupTenSeconds") { table in
            table.column("serverKey", .integer).notNull().references("metricsServer", onDelete: .cascade)
            table.column("startsAt", .integer).notNull()
            table.column("containers", .blob)
            table.column("services", .blob)
            table.primaryKey(["serverKey", "startsAt"])
        }
        // Each hour's busiest container groups and services, named as Hive knew them when the hour closed.
        try database.create(table: "cgroupHour") { table in
            table.column("serverKey", .integer).notNull().references("metricsServer", onDelete: .cascade)
            table.column("startsAt", .integer).notNull()
            table.column("sampleCount", .integer).notNull()
            table.column("containers", .blob).notNull()
            table.column("services", .blob).notNull()
            table.primaryKey(["serverKey", "startsAt"])
        }
        // What `docker ps` said of each container, kept after it's gone so its history keeps its name.
        try database.create(table: "containerName") { table in
            table.column("serverKey", .integer).notNull().references("metricsServer", onDelete: .cascade)
            table.column("containerID", .text).notNull()
            table.column("name", .text)
            table.column("swarmService", .text)
            table.column("composeProject", .text)
            table.column("composeService", .text)
            // Hive's clock, when a sample last had it, so names of long-gone containers are dropped.
            table.column("seenAt", .datetime).notNull()
            table.primaryKey(["serverKey", "containerID"])
        }
        try database.alter(table: "metricsServer") { table in
            // Hive's clock, when it last asked the server for its containers' names.
            table.add(column: "containersAskedAt", .datetime)
            // When `docker ps` last failed, and for which SSH details, so it's asked again only a day
            // later or once they change.
            table.add(column: "dockerFailedAt", .datetime)
            table.add(column: "dockerFailedConnection", .text)
        }
    }

    /// What the Hive Mac's processes that Hive can't read used together.
    private static func addOtherUsersProcesses(_ database: Database) throws {
        for (table, isRollup) in [("serverTenSeconds", false), ("serverMinute", true), ("serverHour", true)] {
            try database.alter(table: table) { table in
                table.add(column: "otherUsersProcesses", .integer)
                if isRollup { table.add(column: "otherUsersProcessesHighest", .integer) }
                table.add(column: "otherUsersCPU", .double)
                if isRollup { table.add(column: "otherUsersCPUHighest", .double) }
            }
        }
    }

    /// A table for each resolution. Rows are always read by key and time, so they're kept in that order
    /// without a row ID, which saves an index as large as the table's keys.
    private static func createFigureTables(_ kind: String, keyedBy parent: String, columns: [FigureColumn], in database: Database) throws {
        let key = parent == "metricsServer" ? "serverKey" : "nameID"
        for (suffix, isRollup) in [("TenSeconds", false), ("Minute", true), ("Hour", true)] {
            try database.create(table: "\(kind)\(suffix)", options: .withoutRowID) { table in
                table.column(key, .integer).notNull().references(parent, onDelete: .cascade)
                table.column("startsAt", .integer).notNull()
                if isRollup { table.column("sampleCount", .integer).notNull() }
                for column in columns {
                    table.column(column.name, column.type)
                    guard isRollup else { continue }
                    if column.kept != .average { table.column("\(column.name)Highest", column.type) }
                    if column.kept == .averageHighestAndLowest { table.column("\(column.name)Lowest", column.type) }
                }
                table.primaryKey([key, "startsAt"])
            }
        }
    }
}
