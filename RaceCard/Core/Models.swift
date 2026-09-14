import Foundation
import Observation

enum Product { static let name = "RaceCard"; static let bundleID = Bundle.main.bundleIdentifier ?? "local.racecard.mac" }
enum Mode: String, CaseIterable, Identifiable { case mock = "Mock", historical = "Historical", replay = "Replay", live = "Live"; var id: String { rawValue } }
struct SessionState: Identifiable, Codable, Equatable {
    var id: Int; var meeting: Int; var title: String; var circuit: String; var type: String; var start: Date; var end: Date; var totalLaps: Int? = nil
    var isRace: Bool { type == "Race" || type == "Sprint" }
    func isLive(at date: Date = Date()) -> Bool { date >= start.addingTimeInterval(-1800) && date <= end.addingTimeInterval(1800) }
}
struct TrackLocationState: Codable, Equatable { var x: Double; var y: Double; var date: Date }
struct LapState: Codable, Equatable { var number: Int; var duration: Double?; var sectors: [Double?]; var speeds: [Double?]; var segments: [[Int]]; var start: Date }
struct StintState: Codable, Equatable, Identifiable { var id: Int; var compound: String; var start: Int; var end: Int?; var initialAge: Int?; var boundaryVerified = true }
/// Stationary service and total lane occupancy are independent, immutable source facts.
struct PitState: Codable, Equatable, Identifiable {
    let id:String;let driver:Int;let lap:Int
    let pitEntryTimestamp:Date
    let pitExitTimestamp:Date?
    let stopDuration:TimeInterval?
    let laneDuration:TimeInterval?
    var date:Date {pitEntryTimestamp}
    init(id:String,driver:Int,lap:Int,date:Date,stopDuration:TimeInterval?,laneDuration:TimeInterval?) {
        self.id=id;self.driver=driver;self.lap=lap;self.pitEntryTimestamp=date
        self.stopDuration=stopDuration;self.laneDuration=laneDuration
        self.pitExitTimestamp=laneDuration.flatMap{$0.isFinite && $0>0 ? date.addingTimeInterval($0):nil}
    }
}
struct TyreChangeState: Codable, Equatable, Identifiable {
    var id: String; var driver: Int; var lap: Int; var date: Date
    var fromCompound: String; var toCompound: String; var priorUsage: Int?
    var pitRecordID: String?; var pitStopDuration: Double?
    var validationStatus: String = "confirmed"
}
struct TelemetryState: Codable, Equatable { var speed: Int?; var gear: Int?; var rpm: Int?; var throttle: Int?; var brake: Int?; var drs: Int?; var date: Date }
struct DriverState: Identifiable, Codable, Equatable {
    var id: Int; var name: String; var acronym: String; var team: String; var color: String
    var familyName: String?; var headshotURL: String?; var previousPosition: Int?; var positionDelta = 0; var movementAt: Date?; var penalty: String?; var investigation = false; var stewardItems:[StewardEvent] = []
    func movement(at now: Date) -> Int { guard let movementAt, now.timeIntervalSince(movementAt) < 4 else { return 0 }; return positionDelta }
    var gridPosition: Int?; var pitStart = false; var positionAt: Date?
    var position: Int?; var gap: String?; var interval: String?; var currentLap = 0; var lastLap: LapState?; var bestLap: LapState?
    var stints: [StintState] = []; var pits: [PitState] = []; var status: String?; var location: TrackLocationState?; var telemetry: TelemetryState?; var lastUpdate: Date?
    // Only records accepted at the replay/live cursor enter this collection.
    var currentStint: StintState? { stints.max { ($0.start,$0.id) < ($1.start,$1.id) } }
    var stintLaps: Int? { guard let stint=currentStint,stint.boundaryVerified else{return nil};return max(0,currentLap-stint.start+1) }
    var tyreAge: Int? { guard let prior = currentStint?.initialAge,let laps = stintLaps else { return nil }; return prior + laps }
}
struct WeatherState: Codable, Equatable { var air: Double?; var track: Double?; var rain: Double?; var humidity: Double?; var wind: Double? }
struct ChampionshipEntry: Identifiable, Codable, Equatable { var id: String; var name: String; var before: Double; var current: Double; var rankBefore: Int; var rankCurrent: Int; var delta: Double { current - before } }
struct ChampionshipState: Codable, Equatable { var drivers: [ChampionshipEntry] = []; var teams: [ChampionshipEntry] = [] }
struct RaceControlState: Codable, Equatable { var flag = ""; var message = ""; var sector: Int?; var phase: RacePhase = .green; var drsEnabled = false; var sectorFlags: [Int:String] = [:]; var timingSectorFlags: [Int:String] = [:] }
struct FeedEvent: Identifiable, Codable, Equatable { var id: String; var order: Int64?; var date: Date; var lap: Int?; var category: String; var text: String; var rawMessage: String? = nil; var driverNumbers: [Int] = []; var facts: RaceEventFacts? = nil; var steward:StewardEvent? = nil;var deletion:LapTimeDeletionEvent? = nil }
struct ConnectionState: Equatable {
    var connected = false; var lastReceived: Date?; var reconnecting = false
    func label(at now: Date) -> String {
        if reconnecting { return "RECONNECTING…" }
        guard connected, let lastReceived else { return "NO DATA" }
        let age = max(0, now.timeIntervalSince(lastReceived))
        return age > 10 ? String(format: "Waiting for data · %.0fs", age) : String(format: "LIVE · %.1fs", age)
    }
}
struct NormalizedRecord: Codable, Identifiable {
    var id: String; var order: Int64?; var date: Date; var kind: String; var driver: Int?; var fields: [String: JSONValue]
}
enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), null
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); if c.decodeNil() { self = .null } else if let b = try? c.decode(Bool.self) { self = .bool(b) } else if let n = try? c.decode(Double.self) { self = .number(n) } else if let s = try? c.decode(String.self) { self = .string(s) } else { self = .array(try c.decode([JSONValue].self)) } }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); switch self { case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .array(let v): try c.encode(v); case .null: try c.encodeNil() } }
    var string: String? { switch self { case .string(let s): return s; case .number(let n): return String(n); default: return nil } }
    var number: Double? { switch self { case .number(let n): return n; case .string(let s): return Double(s); default: return nil } }
    var int: Int? { number.map(Int.init) }; var bool: Bool { self == .bool(true) }
    var array: [JSONValue] { if case .array(let a) = self { return a }; return [] }
}
extension Dictionary where Key == String, Value == JSONValue {
    func s(_ key: String) -> String? { self[key]?.string }; func n(_ key: String) -> Double? { self[key]?.number }; func i(_ key: String) -> Int? { self[key]?.int }; func b(_ key: String) -> Bool { self[key]?.bool ?? false }
}
enum Dates {
    static func parse(_ text: String?) -> Date? { guard let text else { return nil }; let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]; return f.date(from: text) ?? ISO8601DateFormatter().date(from: text) }
    static func iso(_ date: Date) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]; return f.string(from: date) }
}
enum Timing {
    static func lap(_ seconds: Double?, precision: Int = 3) -> String { guard let seconds, seconds.isFinite else { return "—" }; return String(format: "%d:%0*.*f", Int(seconds)/60, precision + 3, precision, seconds.truncatingRemainder(dividingBy: 60)) }
    static func displayGap(_ value: String?, precision: Int) -> String { guard let value else { return "—" }; if let number = Double(value) { return number == 0 ? "—" : String(format:"+%.*f",precision,number) }; return value }
    static func gap(_ value: JSONValue?) -> String? { guard let value, value != .null else { return nil }; if let n = value.number { return n == 0 ? "—" : String(format: "+%.3f", n) }; return value.string }
}
