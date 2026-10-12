import Foundation

/// A row type kept in one table: its columns in a fixed order, its values in that order, and
/// how it is read back.
public protocol TableRow: Sendable {
    static var table: String { get }
    static var columns: [String] { get }
    var values: [any SQLBindable] { get }
    init(row: SQLRow)
}

/// What an insert does when the key is already there.
public enum OnConflict: String, Sendable {
    case abort = ""
    case replace = "OR REPLACE"
    case ignore = "OR IGNORE"
}

extension TableRow {
    static func insertSQL(_ conflict: OnConflict, table: String? = nil) -> String {
        let marks = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        let verb = conflict == .abort ? "INSERT" : "INSERT \(conflict.rawValue)"
        return "\(verb) INTO \(table ?? Self.table) (\(columns.joined(separator: ", "))) VALUES (\(marks))"
    }
}

extension SQLiteDatabase {
    /// Inserts rows, 500 to a transaction step, as one batch.
    public func insert<T: TableRow>(_ rows: [T], _ conflict: OnConflict = .abort) throws {
        guard !rows.isEmpty else { return }
        let sql = T.insertSQL(conflict)
        try transaction { try runEach(sql, rows.map(\.values)) }
    }

    /// Every row a query answers, read as `T`.
    public func rows<T: TableRow>(_ type: T.Type, _ sql: String, _ args: [any SQLBindable] = []) throws -> [T] {
        try query(sql, args) { T(row: $0) }
    }
}
