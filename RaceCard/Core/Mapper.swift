import Foundation

enum OpenF1Mapper {
    static func rows(_ data: Data) throws -> [[String: JSONValue]] { let d = JSONDecoder(); if let rows = try? d.decode([[String: JSONValue]].self, from: data) { return rows }; return [try d.decode([String: JSONValue].self, from: data)] }
    static func session(_ row: [String: JSONValue]) -> SessionState? {
        guard let id = row.i("session_key"), let start = Dates.parse(row.s("date_start")), let end = Dates.parse(row.s("date_end")) else { return nil }
        return SessionState(id: id, meeting: row.i("meeting_key") ?? 0, title: row.s("country_name") ?? "Grand Prix", circuit: row.s("circuit_short_name") ?? row.s("location") ?? "", type: row.s("session_name") ?? "Session", start: start, end: end)
    }
    static func map(_ kind: String, _ row: [String: JSONValue], session: SessionState, received: Date? = nil) -> NormalizedRecord {
        let driver = row.i("driver_number")
        var date = Dates.parse(row.s("date") ?? row.s("date_start")) ?? received ?? session.start
        if kind == "laps", let received { date = received }
        if kind == "laps", received == nil, let duration = row.n("lap_duration") { date = date.addingTimeInterval(duration) }
        if kind == "session_result" || kind.hasPrefix("championship_") { date = received ?? session.end }
        let fallback = [kind, driver.map(String.init) ?? row.s("team_name") ?? "", row.s("lap_number") ?? row.s("stint_number") ?? "", Dates.iso(date), row.s("message") ?? ""].joined(separator: ":")
        return NormalizedRecord(id: kind + ":" + (row.s("_key") ?? fallback), order: row.n("_id").map(Int64.init), date: date, kind: kind, driver: driver, fields: row)
    }
}
enum EventNormalizer {
    static func classification(_ message: String, flag: String = "") -> String {
        let m = message.uppercased()
        if m == "FORMATION LAP" || m == "EXTRA FORMATION LAP" || m.contains("FORMATION LAP STARTED") {return "FORMATION LAP"}
        if m == "STANDING START" {return "START PROCEDURE"}
        if m.contains("GRID FORMING") || m.contains("CARS TAKING GRID POSITIONS") {return "GRID FORMING"}
        if m.contains("PIT LANE START") || m.contains("START FROM THE PIT LANE") || m.contains("STARTING FROM PIT LANE") {return "PIT START"}
        if m.contains("STOPPED") && m.contains("CAR ") { return "CAR STOPPED" }
        if m.contains("RETIRED") { return "RETIRED" }
        if m.contains("BLACK AND WHITE") || m.contains("BLACK & WHITE") {return "BLACK & WHITE FLAG"}
        if m.contains("PENALTY SERVED") { return "PENALTY SERVED" }
        if m.contains("PENALTY WITHDRAWN") { return "PENALTY WITHDRAWN" }
        if m.contains("PENALTY") { return "PENALTY" }
        if m.contains("INVESTIGATION") { return "INVESTIGATION" }
        if m.contains("NOTED") { return "RACE CONTROL" }
        if m.contains("DRS") { return m.contains("DISABLED") ? "DRS DISABLED" : m.contains("ENABLED") ? "DRS ENABLED" : "RACE CONTROL" }
        if flag == "CHEQUERED" || m.contains("SESSION FINISHED") || m.contains("SESSION END") { return "SESSION END" }
        if m.contains("SESSION SUSPENDED") || m == "SESSION STOPPED" { return "SUSPENDED" }
        if m.contains("SESSION RESUMED") || m.contains("SESSION RESTART") { return "RESTART" }
        if flag == "RED" || m.range(of:#"\bRED FLAG\b"#,options:.regularExpression) != nil { return "RED FLAG" }
        if m.range(of:#"(?:VIRTUAL SAFETY CAR|SAFETY CAR|VSC) (?:ENDED|WITHDRAWN)"#,options:.regularExpression) != nil { return "RESTART" }
        if m == "TRACK CLEAR" {return "TRACK CLEAR"}
        if m == "SAFETY CAR LIGHTS ON" || m == "SAFETY CAR LIGHTS OFF" {return "RACE CONTROL"}
        if m.contains("VIRTUAL SAFETY") || m.contains("VSC") { return "VSC" }
        if m.contains("SAFETY CAR") { return "SAFETY CAR" }
        if flag == "DOUBLE YELLOW" || m.contains("DOUBLE YELLOW") { return "DOUBLE YELLOW" }
        if flag.contains("YELLOW") { return "YELLOW FLAG" }
        if m.contains("SESSION START") || m.contains("LIGHTS OUT") || m.contains("RACE STARTED") || m == "RACE START" { return "SESSION START" }
        if flag == "GREEN" || m.contains("GREEN LIGHT") { return "GREEN" }
        if m.contains("STOPPED") && m.contains("CAR ") { return "CAR STOPPED" }
        if m.contains("RETIRED") { return "RETIRED" }
        if m.contains("MECHANICAL") || m.contains("ENGINE FAILURE") || m.contains("GEARBOX FAILURE") { return "MECHANICAL" }
        if m.contains("SESSION START") { return "SESSION START" }
        if m.contains("SESSION END") || flag == "CHEQUERED" { return "SESSION END" }
        return "RACE CONTROL"
    }
    // OpenF1 does not mark pit/penalty exchanges as such; never infer an on-track pass.
    static func overtake(corroboratedOnTrack: Bool) -> String { corroboratedOnTrack ? "OVERTAKE" : "POSITION CHANGE" }
}
struct RecordLedger {
    private var versions: [String: (Int64?, Date)] = [:]
    mutating func accept(_ record: NormalizedRecord) -> Bool {
        if let old = versions[record.id] {
            if let a = old.0, let b = record.order { if b <= a { return false } }
            else if record.date <= old.1 { return false }
        }
        versions[record.id] = (record.order, record.date)
        return true
    }
}
struct ReplayClock {
    static func firstLapStart(session: SessionState, laps: [NormalizedRecord]) -> Date {
        let starts = laps.filter { $0.fields.i("lap_number") == 1 && $0.date < session.end }
            .compactMap { Dates.parse($0.fields.s("date_start")) }
            .filter { $0 >= session.start && $0 < session.end }
        return starts.min() ?? session.start
    }
    static func factualStart(session:SessionState,laps:[NormalizedRecord],control:[NormalizedRecord])->Date {
        let explicit=control.filter {let m=$0.fields.s("message")?.uppercased() ?? "";return m=="LIGHTS OUT" || m=="RACE START" || m=="RACE STARTED" || (m=="SESSION STARTED" && $0.date>=session.start)}.map(\.date).min()
        return explicit ?? firstLapStart(session:session,laps:laps)
    }
    var start: Date; var end: Date; var time: Date; var speed: Double = 1; var playing = false
    mutating func advance(_ elapsed: Double) { guard playing else { return }; seek(time.addingTimeInterval(max(0,elapsed) * speed)); if time >= end { playing = false } }
    mutating func seek(_ date: Date) { time = min(end,max(start,date)) }
}
struct ReconnectPolicy { var attempt = 0; mutating func nextDelay() -> Double { let delay = min(60,pow(2,Double(min(attempt,6)))); attempt += 1; return delay }; mutating func reset() { attempt = 0 } }
