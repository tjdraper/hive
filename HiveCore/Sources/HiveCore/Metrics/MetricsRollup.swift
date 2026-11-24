import GRDB

/// Writes rows into the figure tables, and works out each minute from its 10-second rows and each
/// hour from its minutes (§6).
///
/// A minute's row can come from its 10-second rows or from a minute Scout folded them into while
/// Hive was unreachable. Both cover the same samples, and a request that timed out may have landed,
/// so the row made from more samples wins: a repeat changes nothing, and a late batch that lands in
/// a closed period makes it again.
enum MetricsRollup {
    /// A row's server or name, and the start of its period.
    typealias Row = (key: Int64, startsAt: Int64)

    static func insertSample(_ values: [DatabaseValue], into table: some MetricsTableShape, at row: Row, in database: Database) throws {
        let columns = [table.keyColumn, "startsAt"] + table.figureColumns(.tenSeconds)
        let sql = """
        INSERT INTO \(table.table(.tenSeconds)) (\(columns.joined(separator: ", ")))
        VALUES (\(databaseQuestionMarks(count: columns.count)))
        ON CONFLICT DO NOTHING
        """
        let arguments = StatementArguments([row.key.databaseValue, row.startsAt.databaseValue] + values)
        try database.cachedStatement(sql: sql).execute(arguments: arguments)
    }

    static func insertMinute(
        _ values: [DatabaseValue],
        into table: some MetricsTableShape,
        at row: Row,
        sampleCount: Int,
        in database: Database
    ) throws {
        let columns = [table.keyColumn, "startsAt", "sampleCount"] + table.figureColumns(.minute)
        let sql = """
        INSERT INTO \(table.table(.minute)) (\(columns.joined(separator: ", ")))
        VALUES (\(databaseQuestionMarks(count: columns.count)))
        \(replacing(table, .minute, when: ">"))
        """
        let arguments = StatementArguments([row.key.databaseValue, row.startsAt.databaseValue, sampleCount.databaseValue] + values)
        try database.cachedStatement(sql: sql).execute(arguments: arguments)
    }

    /// Works out the minute or hour starting at `startsAt` for the server's own figures, or for each
    /// of its names of the table's kind, from the resolution below.
    static func rollUp(
        _ table: some MetricsTableShape,
        to resolution: MetricsResolution,
        startingAt startsAt: Int64,
        serverKey: Int64,
        in database: Database
    ) throws {
        let source: MetricsResolution = resolution == .hour ? .minute : .tenSeconds
        let figures = table.columns.flatMap { aggregates(of: $0, from: source) }
        let sampleCount = source == .tenSeconds ? "COUNT(*)" : "SUM(sampleCount)"
        let columns = [table.keyColumn, "startsAt", "sampleCount"] + table.figureColumns(resolution)
        let keys = table.nameKind == nil ? "serverKey = ?" : "nameID IN (SELECT id FROM metricsName WHERE serverKey = ? AND kind = ?)"
        let sql = """
        INSERT INTO \(table.table(resolution)) (\(columns.joined(separator: ", ")))
        SELECT \(table.keyColumn), ?, \(sampleCount), \(figures.joined(separator: ", "))
        FROM \(table.table(source))
        WHERE \(keys) AND startsAt >= ? AND startsAt < ?
        GROUP BY \(table.keyColumn)
        \(replacing(table, resolution, when: ">="))
        """
        var arguments: [DatabaseValue] = [startsAt.databaseValue, serverKey.databaseValue]
        if let kind = table.nameKind { arguments.append(kind.databaseValue) }
        arguments += [startsAt.databaseValue, (startsAt + resolution.seconds).databaseValue]
        try database.cachedStatement(sql: sql).execute(arguments: StatementArguments(arguments))
    }

    /// The average, highest and lowest of a column over rows from `source`, as far as the column keeps them.
    static func aggregates(of column: MetricsColumn, from source: MetricsResolution) -> [String] {
        let name = column.name
        let average: String
        let highest: String
        let lowest: String
        if source == .tenSeconds {
            average = "AVG(\(name))"
            (highest, lowest) = ("MAX(\(name))", "MIN(\(name))")
        } else {
            // Weighted by each minute's samples. TOTAL, unlike SUM, never fails on overflow.
            average = "TOTAL(\(name) * 1.0 * sampleCount) / SUM(CASE WHEN \(name) IS NOT NULL THEN sampleCount END)"
            (highest, lowest) = ("MAX(\(column.highest ?? name))", "MIN(\(column.lowest ?? name))")
        }
        let roundedAverage = column.isWhole ? "CAST(ROUND(\(average)) AS INTEGER)" : average
        return switch column.kept {
        case .average: [roundedAverage]
        case .averageAndHighest: [roundedAverage, highest]
        case .averageHighestAndLowest: [roundedAverage, highest, lowest]
        }
    }

    private static func replacing(_ table: some MetricsTableShape, _ resolution: MetricsResolution, when comparison: String) -> String {
        let target = table.table(resolution)
        let updates = (["sampleCount"] + table.figureColumns(resolution)).map { "\($0) = excluded.\($0)" }
        return """
        ON CONFLICT(\(table.keyColumn), startsAt) DO UPDATE SET \(updates.joined(separator: ", "))
        WHERE excluded.sampleCount \(comparison) \(target).sampleCount
        """
    }
}
