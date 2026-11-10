import Foundation
import GRDB
@testable import HiveCore

extension APIFixture {
    /// Every text and blob value in every table, as bytes, to check a secret isn't stored in the clear.
    func everyStoredValue() throws -> [(table: String, value: Data)] {
        try signIn.database.writer.read { database in
            let tables = try String.fetchAll(database, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            return try tables.flatMap { table in
                try Row.fetchAll(database, sql: "SELECT * FROM \(table.quotedDatabaseIdentifier)").flatMap { row in
                    row.databaseValues.compactMap { value -> (String, Data)? in
                        switch value.storage {
                        case .string(let text): (table, Data(text.utf8))
                        case .blob(let data): (table, data)
                        default: nil
                        }
                    }
                }
            }
        }
    }
}
