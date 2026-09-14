import Foundation
import SQLite3

// Every operation is actor-isolated. WAL and indexed range scans bound replay memory.
actor HistoricalCache {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(path: String) throws {
        guard sqlite3_open(path,&db) == SQLITE_OK else { throw CacheError.database("Cannot open cache") }
        let sql = "PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS records(session INTEGER, key TEXT, time REAL, kind TEXT, driver INTEGER, payload BLOB, PRIMARY KEY(session,key)); CREATE INDEX IF NOT EXISTS timeline ON records(session,time); CREATE INDEX IF NOT EXISTS driver_time ON records(session,kind,driver,time); CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY, payload BLOB); CREATE TABLE IF NOT EXISTS coverage(session INTEGER, resource TEXT, PRIMARY KEY(session,resource));"
        guard sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK else { throw CacheError.database("Cannot initialize cache") }
    }
    deinit { sqlite3_close(db) }
    func metadata(_ key: String) throws -> Data? {
        let s = try statement("SELECT payload FROM metadata WHERE key=?"); defer { sqlite3_finalize(s) }; sqlite3_bind_text(s,1,key,-1,transient)
        guard sqlite3_step(s) == SQLITE_ROW, let bytes = sqlite3_column_blob(s,0) else { return nil }; return Data(bytes:bytes,count:Int(sqlite3_column_bytes(s,0)))
    }
    func metadata(_ key: String, data: Data) throws {
        let s = try statement("INSERT OR REPLACE INTO metadata VALUES(?,?)"); defer { sqlite3_finalize(s) }; sqlite3_bind_text(s,1,key,-1,transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(s,2,$0.baseAddress,Int32(data.count),transient) }; guard sqlite3_step(s) == SQLITE_DONE else { throw CacheError.database("Metadata write failed") }
    }
    enum CacheError: Error { case database(String) }
    private func statement(_ sql: String) throws -> OpaquePointer { var s: OpaquePointer?; guard sqlite3_prepare_v2(db,sql,-1,&s,nil) == SQLITE_OK, let s else { throw CacheError.database(String(cString:sqlite3_errmsg(db))) }; return s }
    func write(_ records: [NormalizedRecord], session: Int) throws {
        try execute("BEGIN IMMEDIATE"); do {
            let s = try statement("INSERT OR REPLACE INTO records VALUES(?,?,?,?,?,?)"); defer { sqlite3_finalize(s) }
            for r in records { let data = try JSONEncoder().encode(r); sqlite3_bind_int(s,1,Int32(session)); sqlite3_bind_text(s,2,r.id,-1,transient); sqlite3_bind_double(s,3,r.date.timeIntervalSince1970); sqlite3_bind_text(s,4,r.kind,-1,transient); sqlite3_bind_int(s,5,Int32(r.driver ?? 0)); _ = data.withUnsafeBytes { sqlite3_bind_blob(s,6,$0.baseAddress,Int32(data.count),transient) }; guard sqlite3_step(s) == SQLITE_DONE else { throw CacheError.database("Cache write failed") }; sqlite3_reset(s); sqlite3_clear_bindings(s) }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    private func execute(_ sql: String) throws { guard sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK else { throw CacheError.database(String(cString: sqlite3_errmsg(db))) } }
    func has(_ resource: String, session: Int) throws -> Bool { let s = try statement("SELECT 1 FROM coverage WHERE session=? AND resource=?"); defer { sqlite3_finalize(s) }; sqlite3_bind_int(s,1,Int32(session)); sqlite3_bind_text(s,2,resource,-1,transient); return sqlite3_step(s) == SQLITE_ROW }
    func mark(_ resource: String, session: Int) throws { let s = try statement("INSERT OR IGNORE INTO coverage VALUES(?,?)"); defer { sqlite3_finalize(s) }; sqlite3_bind_int(s,1,Int32(session)); sqlite3_bind_text(s,2,resource,-1,transient); guard sqlite3_step(s) == SQLITE_DONE else { throw CacheError.database("Coverage write failed") } }
    func read(session: Int, after: Date, through: Date, kind: String? = nil, driver: Int? = nil, limit: Int = 10000, offset: Int = 0, rebuild: Bool = false, locationAfter:Date? = nil) throws -> [NormalizedRecord] {
        var sql = "SELECT payload FROM records WHERE session=? AND time>? AND time<=?"; if kind != nil { sql += " AND kind=?" }; if driver != nil { sql += " AND driver=?" }; if rebuild {sql += " AND kind != 'car_data'"}; if locationAfter != nil {sql += " AND (kind != 'location' OR time>?)"}; sql += " ORDER BY time,key LIMIT ? OFFSET ?"
        let s = try statement(sql); defer { sqlite3_finalize(s) }; sqlite3_bind_int(s,1,Int32(session)); sqlite3_bind_double(s,2,after.timeIntervalSince1970); sqlite3_bind_double(s,3,through.timeIntervalSince1970)
        var i: Int32 = 4; if let kind { sqlite3_bind_text(s,i,kind,-1,transient); i += 1 }; if let driver { sqlite3_bind_int(s,i,Int32(driver)); i += 1 }; if let locationAfter {sqlite3_bind_double(s,i,locationAfter.timeIntervalSince1970);i += 1}; sqlite3_bind_int(s,i,Int32(limit)); sqlite3_bind_int(s,i+1,Int32(offset))
        var result: [NormalizedRecord] = []; while sqlite3_step(s) == SQLITE_ROW { let count = Int(sqlite3_column_bytes(s,0)); if let bytes = sqlite3_column_blob(s,0) { result.append(try JSONDecoder().decode(NormalizedRecord.self,from:Data(bytes:bytes,count:count))) } }; return result
    }
    func cachedDriverSnapshots() throws -> [DriverSnapshot] {
        let statement=try statement("SELECT session,payload FROM records WHERE kind='drivers' ORDER BY time")
        defer {sqlite3_finalize(statement)}
        var result:[DriverSnapshot]=[]
        while sqlite3_step(statement)==SQLITE_ROW {
            let session=Int(sqlite3_column_int(statement,0))
            guard let bytes=sqlite3_column_blob(statement,1) else {continue}
            let record=try JSONDecoder().decode(NormalizedRecord.self,from:Data(bytes:bytes,count:Int(sqlite3_column_bytes(statement,1))))
            guard let number=record.driver,let name=record.fields.s("full_name"),!name.isEmpty else {continue}
            result.append(.init(identityID:DriverRegistry.stableID(name),season:Calendar(identifier:.gregorian).component(.year,from:record.date),sessionKey:session,meetingKey:record.fields.i("meeting_key") ?? 0,date:Dates.iso(record.date),number:number,fullName:name,acronym:record.fields.s("name_acronym") ?? "",team:record.fields.s("team_name") ?? "",teamColor:record.fields.s("team_colour") ?? "888888",headshotURL:record.fields.s("headshot_url"),sourceURL:"https://api.openf1.org/v1/drivers?session_key=\(session)"))
        }
        return result
    }
    func count(session: Int) throws -> Int { let s = try statement("SELECT COUNT(*) FROM records WHERE session=?"); defer { sqlite3_finalize(s) }; sqlite3_bind_int(s,1,Int32(session)); _ = sqlite3_step(s); return Int(sqlite3_column_int64(s,0)) }
}
