import Foundation
import GRDB
import HiveKit

/// A server's figures over a range, for Beekeeper's charts, in buckets sized so any range comes back
/// as at most a few hundred (§6).
///
/// Each stretch of the range is read from whichever resolution holds the most samples for it. Minutes a
/// Scout held while Hive was unreachable have no 10-second rows, so reading one resolution for the
/// whole range would show them as a gap.
struct MetricsSeriesReader: Sendable {
    static let largestBucketCount: Int64 = 600
    /// Each divides every longer one up to an hour, or is a multiple of an hour, so a bucket never
    /// splits a row of a resolution no longer than it, and a minute or an hour holds whole buckets.
    private static let bucketSizes: [Int64] = [
        10, 20, 30, 60, 120, 180, 300, 600, 900, 1_200, 1_800,
        3_600, 7_200, 10_800, 14_400, 21_600, 43_200, 86_400,
    ]

    let database: MetricsDatabase
    let now: @Sendable () -> Date

    /// Never finer than the finest resolution still kept at the range's start, so an older range isn't
    /// split into buckets its rows can't fill. Rows are pruned hourly, so a range of exactly a week,
    /// which reaches Hive a few seconds older than when Beekeeper asked, still reads minutes.
    static func bucketSeconds(for range: Range<Int64>, serverNow: Int64) -> Int64 {
        let pruningSlack = Int64(MetricsUpkeep.interval.components.seconds)
        let finest = MetricsResolution.allCases.first { range.lowerBound >= serverNow - $0.keptSeconds - pruningSlack } ?? .hour
        let smallest = max(finest.seconds, (Int64(range.count) + largestBucketCount - 1) / largestBucketCount)
        if let size = bucketSizes.first(where: { $0 >= smallest }) { return size }
        let day: Int64 = 86_400
        return (smallest + day - 1) / day * day
    }

    /// `range` is seconds since 1970 on the server's clock.
    func series(ofServer serverID: UUID, over range: Range<Int64>, figures: [MetricsFigure]) throws -> MetricsSeries {
        let hiveNow = Int64(now().timeIntervalSince1970.rounded(.down))
        var unique: [MetricsFigure] = []
        for figure in figures where !unique.contains(figure) {
            unique.append(figure)
        }
        return try database.writer.read { database in
            let server = try Row.fetchOne(
                database,
                sql: "SELECT id, clockOffsetSeconds FROM metricsServer WHERE serverID = ?",
                arguments: [serverID]
            )
            let offset: Int64 = server?["clockOffsetSeconds"] ?? 0
            let bucketSeconds = Self.bucketSeconds(for: range, serverNow: hiveNow + offset)
            guard let serverKey: Int64 = server?["id"] else { return MetricsSeries(bucketSeconds: bucketSeconds, subjects: []) }

            let subjects = try MetricsTables.all.flatMap { table in
                let wanted = unique.compactMap { figure in
                    figure.stored.flatMap { $0.table.kind == table.kind ? (figure, $0.column) : nil }
                }
                guard !wanted.isEmpty else { return [MetricsSeriesSubject]() }
                let reading = SubjectReading(table: table, figures: wanted, serverKey: serverKey, bucketSeconds: bucketSeconds)
                return try reading.subjects(over: range, in: database)
            }
            return MetricsSeries(bucketSeconds: bucketSeconds, subjects: subjects)
        }
    }
}

/// One table's figures for a server, bucketed.
private struct SubjectReading {
    /// A row of one resolution, or a bucket's worth of them. Pieces never overlap.
    private struct Piece {
        /// The server's, or the name's the figures are kept under.
        let subjectKey: Int64
        let start: Int64
        let seconds: Int64
        let samples: Int
        /// Each figure's average, then its highest and lowest where it keeps them.
        let values: [Double?]
    }

    let table: any MetricsTableShape
    let figures: [(MetricsFigure, MetricsColumn)]
    let serverKey: Int64
    let bucketSeconds: Int64

    func subjects(over range: Range<Int64>, in database: Database) throws -> [MetricsSeriesSubject] {
        let firstBucket = Self.floor(range.lowerBound, to: bucketSeconds)
        // By subject, then by start.
        var pieces: [Int64: [Int64: Piece]] = [:]
        // Finest first, so a coarser row replaces what's there only when it holds more samples.
        for source in MetricsResolution.allCases {
            let seconds = max(bucketSeconds, source.seconds)
            let read = Self.floor(firstBucket, to: seconds) ..< range.upperBound
            for piece in try self.read(source, inPiecesOf: seconds, over: read, in: database) {
                let (key, start) = (piece.subjectKey, piece.start)
                let inside = pieces[key, default: [:]].filter { $0.key >= start && $0.key < start + seconds }
                guard piece.samples > inside.values.reduce(0, { $0 + $1.samples }) else { continue }
                for replaced in inside.keys {
                    pieces[key]?.removeValue(forKey: replaced)
                }
                pieces[key, default: [:]][start] = piece
            }
        }

        let kind = MetricsSubjectKind(rawValue: table.kind) ?? .server
        let names = try self.names(in: database)
        let subjects = pieces.compactMap { key, byStart -> MetricsSeriesSubject? in
            let name = names[key]
            guard table.nameKind == nil || name != nil else { return nil }
            var starts: [Int64] = []
            var buckets: [[Double?]] = []
            // A piece longer than a bucket gives each bucket it covers its figures.
            for (start, piece) in byStart.sorted(by: { $0.key < $1.key }) {
                let end = min(start + piece.seconds, range.upperBound)
                for bucket in stride(from: max(start, firstBucket), to: end, by: Int(bucketSeconds)) {
                    starts.append(bucket)
                    buckets.append(piece.values)
                }
            }
            guard !starts.isEmpty else { return nil }
            return MetricsSeriesSubject(kind: kind, name: name, bucketStarts: starts, figures: figureSeries(buckets))
        }
        return subjects.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private func read(
        _ source: MetricsResolution,
        inPiecesOf seconds: Int64,
        over range: Range<Int64>,
        in database: Database
    ) throws -> [Piece] {
        let aggregates = figures.flatMap { MetricsRollup.aggregates(of: $0.1, from: source) }
        let samples = source == .tenSeconds ? "COUNT(*)" : "SUM(sampleCount)"
        let keys = table.nameKind == nil ? "serverKey = ?" : "nameID IN (SELECT id FROM metricsName WHERE serverKey = ? AND kind = ?)"
        let sql = """
        SELECT \(table.keyColumn) AS subjectKey, startsAt / \(seconds) * \(seconds) AS pieceStart, \(samples),
            \(aggregates.joined(separator: ", "))
        FROM \(table.table(source))
        WHERE \(keys) AND startsAt >= ? AND startsAt < ?
        GROUP BY subjectKey, pieceStart
        """
        var arguments: [DatabaseValue] = [serverKey.databaseValue]
        if let kind = table.nameKind { arguments.append(kind.databaseValue) }
        arguments += [range.lowerBound.databaseValue, range.upperBound.databaseValue]
        return try Row.fetchAll(database, sql: sql, arguments: StatementArguments(arguments)).map { row in
            let values = (3 ..< row.count).map { row[$0] as Double? }
            return Piece(subjectKey: row[0], start: row[1], seconds: seconds, samples: row[2], values: values)
        }
    }

    private func names(in database: Database) throws -> [Int64: String] {
        guard let kind = table.nameKind else { return [:] }
        let rows = try Row.fetchAll(
            database,
            sql: "SELECT id, name FROM metricsName WHERE serverKey = ? AND kind = ?",
            arguments: [serverKey, kind]
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0["id"], $0["name"]) })
    }

    private func figureSeries(_ buckets: [[Double?]]) -> [MetricsFigureSeries] {
        var offset = 0
        return figures.map { figure, column in
            let first = offset
            func values(_ index: Int) -> [Double?] {
                buckets.map { $0[first + index] }
            }
            offset += 1 + (column.highest == nil ? 0 : 1) + (column.lowest == nil ? 0 : 1)
            return MetricsFigureSeries(
                figure: figure,
                average: values(0),
                highest: column.highest == nil ? nil : values(1),
                lowest: column.lowest == nil ? nil : values(column.highest == nil ? 1 : 2)
            )
        }
    }

    private static func floor(_ time: Int64, to seconds: Int64) -> Int64 {
        time - ((time % seconds) + seconds) % seconds
    }
}

extension MetricsFigure {
    /// The table and column Hive keeps the figure in.
    var stored: (table: any MetricsTableShape, column: MetricsColumn)? {
        guard let table = MetricsTables.all.first(where: { $0.kind == subject.rawValue }),
              let column = table.columns.first(where: { $0.name == name })
        else { return nil }
        return (table, column)
    }
}
