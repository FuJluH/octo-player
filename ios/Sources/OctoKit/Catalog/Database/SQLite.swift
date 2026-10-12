import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

/// One value going into or coming out of the database.
public enum SQLValue: Sendable, Equatable {
    case null
    case int(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

/// Anything that can be bound to a `?` in a statement.
public protocol SQLBindable {
    var sqlValue: SQLValue { get }
}

extension String: SQLBindable { public var sqlValue: SQLValue { .text(self) } }
extension Int: SQLBindable { public var sqlValue: SQLValue { .int(Int64(self)) } }
extension Int64: SQLBindable { public var sqlValue: SQLValue { .int(self) } }
extension Int32: SQLBindable { public var sqlValue: SQLValue { .int(Int64(self)) } }
extension Double: SQLBindable { public var sqlValue: SQLValue { .real(self) } }
extension Float: SQLBindable { public var sqlValue: SQLValue { .real(Double(self)) } }
extension Bool: SQLBindable { public var sqlValue: SQLValue { .int(self ? 1 : 0) } }
extension Data: SQLBindable { public var sqlValue: SQLValue { .blob(self) } }
extension SQLValue: SQLBindable { public var sqlValue: SQLValue { self } }

extension Optional: SQLBindable where Wrapped: SQLBindable {
    public var sqlValue: SQLValue {
        switch self {
        case .some(let value): value.sqlValue
        case .none: .null
        }
    }
}

public struct SQLiteError: Error, CustomStringConvertible, Equatable {
    public var code: Int32
    public var message: String

    public var description: String { "SQLite error \(code): \(message)" }
}

/// SQLite's own word for "copy the bytes now".
private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One open database. Not safe to share between threads: the catalog's actor owns it.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private var statements: [String: Statement] = [:]
    private var depth = 0

    /// Opens (or makes) the database at `path`; ":memory:" keeps it in memory.
    public init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let status = sqlite3_open_v2(path, &db, flags, nil)
        guard status == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open"
            sqlite3_close(db)
            throw SQLiteError(code: status, message: message)
        }
        handle = db
        sqlite3_busy_timeout(db, 5_000)
        try execute("PRAGMA foreign_keys = ON")
        if path != ":memory:" { try execute("PRAGMA journal_mode = WAL") }
    }

    deinit {
        for statement in statements.values { sqlite3_finalize(statement.pointer) }
        sqlite3_close(handle)
    }

    /// Runs one or more statements with nothing bound and nothing read back.
    public func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &error)
        if status != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastMessage
            sqlite3_free(error)
            throw SQLiteError(code: status, message: message)
        }
    }

    /// Runs one statement with its `?` marks bound in order.
    public func run(_ sql: String, _ args: [any SQLBindable] = []) throws {
        let statement = try prepare(sql)
        defer { statement.reset() }
        try statement.bind(args)
        try statement.stepToEnd(self)
    }

    /// Runs one statement once for each set of values, as in a batch insert.
    public func runEach(_ sql: String, _ rows: [[any SQLBindable]]) throws {
        guard !rows.isEmpty else { return }
        let statement = try prepare(sql)
        for args in rows {
            defer { statement.reset() }
            try statement.bind(args)
            try statement.stepToEnd(self)
        }
    }

    /// Reads every row a query answers.
    public func query<T>(_ sql: String, _ args: [any SQLBindable] = [], _ read: (SQLRow) throws -> T) throws -> [T] {
        let statement = try prepare(sql)
        defer { statement.reset() }
        try statement.bind(args)
        var rows: [T] = []
        while true {
            let status = sqlite3_step(statement.pointer)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw SQLiteError(code: status, message: lastMessage) }
            rows.append(try read(SQLRow(statement: statement)))
        }
        return rows
    }

    /// The first row a query answers, or nil.
    public func first<T>(_ sql: String, _ args: [any SQLBindable] = [], _ read: (SQLRow) throws -> T) throws -> T? {
        try query(sql, args, read).first
    }

    /// One whole number a query answers, such as a count; 0 when it answers nothing.
    public func scalar(_ sql: String, _ args: [any SQLBindable] = []) throws -> Int64 {
        try first(sql, args) { $0.int64(at: 0) } ?? 0
    }

    /// Strings from a query's first column.
    public func strings(_ sql: String, _ args: [any SQLBindable] = []) throws -> [String] {
        try query(sql, args) { $0.string(at: 0) }
    }

    /// Runs `body` inside one transaction: everything it writes lands at once, or nothing does.
    /// Nested calls join the outer transaction.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        if depth > 0 {
            depth += 1
            defer { depth -= 1 }
            return try body()
        }
        try execute("BEGIN IMMEDIATE")
        depth = 1
        do {
            let value = try body()
            depth = 0
            try execute("COMMIT")
            return value
        } catch {
            depth = 0
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Rows the last write changed.
    public var changes: Int { Int(sqlite3_changes(handle)) }

    /// The row id the last insert made.
    public var lastInsertRowId: Int64 { sqlite3_last_insert_rowid(handle) }

    /// The schema version kept in the file.
    public var userVersion: Int {
        get { Int((try? scalar("PRAGMA user_version")) ?? 0) }
        set { try? execute("PRAGMA user_version = \(newValue)") }
    }

    fileprivate var lastMessage: String { String(cString: sqlite3_errmsg(handle)) }

    private func prepare(_ sql: String) throws -> Statement {
        if let cached = statements[sql] { return cached }
        var pointer: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &pointer, nil)
        guard status == SQLITE_OK, let pointer else { throw SQLiteError(code: status, message: lastMessage + " in: " + sql) }
        let statement = Statement(pointer)
        statements[sql] = statement
        return statement
    }
}

/// A prepared statement, kept for reuse.
final class Statement {
    let pointer: OpaquePointer
    private var columns: [String: Int32]?

    init(_ pointer: OpaquePointer) { self.pointer = pointer }

    func reset() {
        sqlite3_reset(pointer)
        sqlite3_clear_bindings(pointer)
    }

    func bind(_ args: [any SQLBindable]) throws {
        for (offset, arg) in args.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32 = switch arg.sqlValue {
            case .null: sqlite3_bind_null(pointer, index)
            case .int(let value): sqlite3_bind_int64(pointer, index, value)
            case .real(let value): sqlite3_bind_double(pointer, index, value)
            case .text(let value): sqlite3_bind_text(pointer, index, value, -1, transient)
            case .blob(let value): value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(pointer, index, bytes.baseAddress, Int32(bytes.count), transient)
            }
            }
            guard status == SQLITE_OK else { throw SQLiteError(code: status, message: "could not bind value \(index)") }
        }
    }

    func stepToEnd(_ db: SQLiteDatabase) throws {
        while true {
            let status = sqlite3_step(pointer)
            if status == SQLITE_DONE { return }
            if status != SQLITE_ROW { throw SQLiteError(code: status, message: db.lastMessage) }
        }
    }

    func column(_ name: String) -> Int32? {
        if columns == nil {
            var found: [String: Int32] = [:]
            for index in 0..<sqlite3_column_count(pointer) {
                let name = String(cString: sqlite3_column_name(pointer, index))
                // The first column of a name wins, as in `t.*` followed by extras.
                if found[name] == nil { found[name] = index }
            }
            columns = found
        }
        return columns?[name]
    }
}

/// One row of an answer, read by column name or place.
public struct SQLRow {
    let statement: Statement

    private var pointer: OpaquePointer { statement.pointer }

    private func index(_ name: String) -> Int32 {
        guard let index = statement.column(name) else { preconditionFailure("no column \(name)") }
        return index
    }

    public func has(_ name: String) -> Bool { statement.column(name) != nil }

    public func isNull(at index: Int32) -> Bool { sqlite3_column_type(pointer, index) == SQLITE_NULL }
    public func isNull(_ name: String) -> Bool { isNull(at: index(name)) }

    public func string(at index: Int32) -> String {
        guard let text = sqlite3_column_text(pointer, index) else { return "" }
        return String(cString: text)
    }

    public func int64(at index: Int32) -> Int64 { sqlite3_column_int64(pointer, index) }

    public func string(_ name: String) -> String { string(at: index(name)) }
    public func optionalString(_ name: String) -> String? { isNull(name) ? nil : string(name) }
    public func int(_ name: String) -> Int { Int(int64(at: index(name))) }
    public func optionalInt(_ name: String) -> Int? { isNull(name) ? nil : int(name) }
    public func int64(_ name: String) -> Int64 { int64(at: index(name)) }
    public func optionalInt64(_ name: String) -> Int64? { isNull(name) ? nil : int64(name) }
    public func double(_ name: String) -> Double { sqlite3_column_double(pointer, index(name)) }
    public func optionalFloat(_ name: String) -> Float? { isNull(name) ? nil : Float(double(name)) }
    public func float(_ name: String) -> Float { Float(double(name)) }
    public func bool(_ name: String) -> Bool { int64(name) != 0 }
    public func optionalBool(_ name: String) -> Bool? { isNull(name) ? nil : bool(name) }
}
