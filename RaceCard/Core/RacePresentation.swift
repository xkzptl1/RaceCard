import Foundation
import RaceCardDataKit

struct DriverNameResolver {
    static let japaneseFullNames = ["NOR":"ランド・ノリス","VER":"マックス・フェルスタッペン","LEC":"シャルル・ルクレール","PIA":"オスカー・ピアストリ","RUS":"ジョージ・ラッセル","HAM":"ルイス・ハミルトン","ALO":"フェルナンド・アロンソ","SAI":"カルロス・サインツ","STR":"ランス・ストロール","TSU":"角田裕毅","GAS":"ピエール・ガスリー","OCO":"エステバン・オコン","ALB":"アレクサンダー・アルボン","HUL":"ニコ・ヒュルケンベルグ","LAW":"リアム・ローソン","BEA":"オリバー・ベアマン","HAD":"アイザック・ハジャー","BOR":"ガブリエル・ボルトレト","ANT":"キミ・アントネッリ","DOO":"ジャック・ドゥーハン","PER":"セルジオ・ペレス","BOT":"バルテリ・ボッタス","COL":"フランコ・コラピント","MAG":"ケビン・マグヌッセン","RIC":"ダニエル・リカルド","ZHO":"周冠宇","SAR":"ローガン・サージェント"]
    @MainActor static func full(_ driver:DriverState)->String { Localization.shared.language == "ja" ? japaneseFullNames[driver.acronym] ?? driver.name : driver.name }
    static let surnames = ["VER":"フェルスタッペン","NOR":"ノリス","PIA":"ピアストリ","RUS":"ラッセル","ANT":"アントネッリ","HAM":"ハミルトン","LEC":"ルクレール","ALO":"アロンソ","STR":"ストロール","ALB":"アルボン","SAI":"サインツ","GAS":"ガスリー","COL":"コラピント","OCO":"オコン","BEA":"ベアマン","HUL":"ヒュルケンベルグ","BOR":"ボルトレト","LAW":"ローソン","TSU":"角田","PER":"ペレス","BOT":"ボッタス","HAD":"ハジャー","MAG":"マグヌッセン","RIC":"リカルド","ZHO":"周","SAR":"サージェント","DOO":"ドゥーハン"]
    static let fullNames = ["VER":"Max Verstappen","NOR":"Lando Norris","PIA":"Oscar Piastri","RUS":"George Russell","ANT":"Kimi Antonelli","HAM":"Lewis Hamilton","LEC":"Charles Leclerc","ALO":"Fernando Alonso","STR":"Lance Stroll","ALB":"Alexander Albon","SAI":"Carlos Sainz","GAS":"Pierre Gasly","COL":"Franco Colapinto","OCO":"Esteban Ocon","BEA":"Oliver Bearman","HUL":"Nico Hulkenberg","BOR":"Gabriel Bortoleto","LAW":"Liam Lawson","TSU":"Yuki Tsunoda","PER":"Sergio Perez","BOT":"Valtteri Bottas","HAD":"Isack Hadjar","MAG":"Kevin Magnussen","RIC":"Daniel Ricciardo","ZHO":"Zhou Guanyu","SAR":"Logan Sargeant","DOO":"Jack Doohan"]
    static func japanese(_ driver: DriverState) -> String { surnames[driver.acronym] ?? driver.familyName ?? driver.name.split(separator:" ").last.map(String.init) ?? driver.acronym }
}
enum RacePhase: String, Codable { case green, safetyCar, virtualSafetyCar, red, finished }
struct MapNotice: Identifiable, Equatable { var id: String; var category: String; var text: String; var shownAt: Date?; var driver:Int?; var event:FeedEvent? = nil
    var priority: Int { ["RED FLAG":100,"SUSPENDED":100,"SAFETY CAR":90,"VSC":80,"CAR STOPPED":70,"RETIRED":70,"MECHANICAL":70,"PENALTY":60,"INVESTIGATION":50,"RESTART":40,"FASTEST LAP":30][category] ?? 0 }
    var duration: Double { ["PENALTY","CAR STOPPED","RETIRED","MECHANICAL","INVESTIGATION","FASTEST LAP"].contains(category) ? 7 : category == "INVESTIGATION" ? 6 : 5 }
}

struct TrackSector: Codable, Equatable { var number: Int; var sourceSectors: [Int]; var points: [TrackPoint]; var label: TrackPoint }
struct DRSZone: Codable, Equatable { var detectionPoint: TrackPoint?; var points: [TrackPoint]; var label: String? }
struct CornerMarker: Codable, Equatable { var label: String; var point: TrackPoint }
struct TrackMetadata: Codable, Equatable {
    var circuitKey: String; var coordinateSession: Int? = nil; var source: String; var verified: Bool; var sectors: [TrackSector]; var drsZones: [DRSZone]
    var pitEntry: TrackPoint?; var pitExit: TrackPoint?; var startFinish: TrackPoint?; var corners: [CornerMarker]
    static func load(circuit: String, session: Int? = nil) -> TrackMetadata? {
        let dir = RaceCardStorage.applicationSupport
        let safe = circuit.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let url = dir.appendingPathComponent("TrackMetadata/\(safe).json")
        let data = (try? Data(contentsOf:url)) ?? (session == 9165 && circuit == "Singapore" ? Bundle.main.url(forResource:"track_singapore_9165",withExtension:"json").flatMap { try? Data(contentsOf:$0) } : nil)
        guard let data,let m = try? JSONDecoder().decode(Self.self,from:data),m.verified,!m.source.isEmpty,m.circuitKey == circuit,(m.coordinateSession == nil || m.coordinateSession == session) else { return nil }; return m
    }
    // This circuit is authored by RaceCard: every overlay uses its exact analytic XY definition.
    static var fixture: TrackMetadata {
        func p(_ phase: Double) -> TrackPoint { let l = MockF1Provider.point(phase,date:MockF1Provider.start); return .init(x:l.x,y:l.y) }
        return .init(circuitKey:"racecard-fixture",source:"MockF1Provider.point: authored test circuit, not a real-world circuit",verified:true,sectors:(0..<3).map { n in .init(number:n+1,sourceSectors:[n+1],points:(0...80).map { p(Double(n)/3+Double($0)/240) },label:p(Double(n)/3+0.15)) },drsZones:[.init(detectionPoint:p(0.03),points:(15...47).map { p(Double($0)/240) },label:"DRS 1")],pitEntry:p(0.91),pitExit:p(0.06),startFinish:p(0),corners:[.init(label:"T8",point:p(0.6))])
    }
}
struct StatusRail: Equatable {
    var gap: String; var pill: String?; var replacesGap: Bool
    static func resolve(driver d: DriverState, state: String?, drsEnabled: Bool, precision: Int, isRace: Bool) -> Self {
        let critical = ["DSQ","DNF","DNS","OUT","STOP","STOPPED","RETIRED"]
        let gap = isRace ? (d.position == 1 ? "LEADER" : Timing.displayGap(d.gap,precision:precision)) : Timing.lap(d.bestLap?.duration,precision:precision)
        if d.penalty == "DSQ" {return .init(gap:gap,pill:"DSQ",replacesGap:true)}
        if let state,critical.contains(state) { return .init(gap:gap,pill:state == "STOPPED" ? "STOP" : state == "RETIRED" ? "OUT" : state,replacesGap:true) }
        let drs = drsEnabled && (d.telemetry?.drs.map { [10,12,14].contains($0) } ?? false)
        return .init(gap:gap,pill:d.penalty ?? (state == "PIT" ? "PIT" : d.investigation ? (d.stewardItems.first(where:{$0.state == .investigation})?.compact ?? "INV") : drs ? "DRS" : state == "STALE" ? "STALE" : nil),replacesGap:false)
    }
}
enum JapaneseRaceText {
    static func capture(_ pattern: String,_ text: String) -> [String]? {
        guard let r = try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),let m = r.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { return nil }
        return (1..<m.numberOfRanges).map { Range(m.range(at:$0),in:text).map { String(text[$0]) } ?? "" }
    }
    static func driverIDs(_ message:String)->[Int] {
        guard let list=capture(#"\bCARS?\s+((?:\d+\s*(?:\([A-Z]{3}\))?\s*(?:,|AND|&)?\s*)+)"#,message)?.first else { return [] }
        return list.components(separatedBy:CharacterSet.decimalDigits.inverted).compactMap(Int.init)
    }
    static func driverID(_ message: String) -> Int? { capture( #"\bCARS?\s+(\d+)\b"#,message)?.first.flatMap(Int.init) }
    static func penalty(_ message: String) -> String? {
        if let n = capture(#"\b(\d+)\s*(?:SECOND|SEC|S)\s+(?:TIME\s+)?PENALTY"#,message)?.first { return "+\(n)s" }
        if message.contains("DRIVE THROUGH") || message.contains("DRIVE-THROUGH") { return "DT" }
        if message.contains("STOP GO") || message.contains("STOP-GO") { return "SG" }; return nil
    }
    static func text(category: String, raw: String, driver: String?, sector: Int? = nil) -> String {
        let m = raw.uppercased(); let who = driver ?? driverID(m).map { "\($0)号車" } ?? "対象車両"
        let sectorNumber = sector ?? capture(#"(?:TRACK\s+)?SECTOR\s+(\d+)"#,m)?.first.flatMap(Int.init)
        let whereText = sectorNumber.map { "RC\($0)で" } ?? ""
        if m.contains("PIT EXIT CLOSED") { return "ピット出口閉鎖" }
        if m.contains("PIT EXIT OPEN") { return "ピット出口開放" }
        switch category {
        case "FORMATION LAP": return m.contains("EXTRA") ? "追加フォーメーションラップ" : "フォーメーションラップ"
        case "START PROCEDURE": return "スタンディングスタート"
        case "GRID FORMING": return "スターティンググリッドへ整列中"
        case "PIT START": return "\(who)がピットレーンからスタート"
        case "SAFETY CAR": return m.contains("IN THIS LAP") ? "セーフティカーはこの周で終了予定" : "セーフティカー導入"
        case "VSC": return m.contains("ENDING") ? "バーチャルセーフティカー終了予定" : "バーチャルセーフティカー導入"
        case "SECTOR RED": return whereText+"赤旗"
        case "RED FLAG": return "赤旗・セッション中断"
        case "SUSPENDED": return "セッション中断"
        case "RESTART": return m.contains("SAFETY CAR") || m.contains("VSC") ? "セーフティカー規制終了・走行再開" : "セッション再開"
        case "YELLOW FLAG": return whereText+"黄旗"
        case "DOUBLE YELLOW": return whereText+"ダブルイエロー"
        case "GREEN": return "グリーン・走行再開"
        case "DRS ENABLED": return "DRS使用可能"
        case "DRS DISABLED": return "DRS使用停止"
        case "PENALTY SERVED": return "\(who)がペナルティを消化"
        case "PENALTY WITHDRAWN": return "\(who)のペナルティを撤回"
        case "PENALTY": if let p = penalty(m) { return p == "DT" ? "\(who)にドライブスルーペナルティ" : p == "SG" ? "\(who)にストップ＆ゴーペナルティ" : "\(who)に\(p.dropFirst().dropLast())秒ペナルティ" }; return "\(who)にペナルティ通知"
        case "INVESTIGATION": return m.contains("NO FURTHER") ? "\(who)の追加審議なし" : "\(who)が審議対象"
        case "CAR STOPPED": return "\(who)が停止"
        case "RETIRED": return "\(who)がリタイア"
        case "MECHANICAL": return "\(who)の機械的トラブルを公式確認"
        case "SESSION START": return "セッション開始"
        case "SESSION END": return "セッション終了"
        default:
            if m.contains("PIT EXIT CLOSED") { return "ピット出口閉鎖" }
            if m.contains("PIT EXIT OPEN") { return "ピット出口開放" }
            if let chance=capture(#"RISK OF RAIN.*?(\d+)%"#,m)?.first { return "公式降雨確率：\(chance)%" }
            if m.contains("TIME"),m.contains("DELETED"),let time=capture(#"TIME\s+([0-9:.]+)"#,m)?.first { return "\(who)のタイム\(time)を抹消" }
            return "レースコントロール通知" + (sectorNumber.map { "・セクター\($0)" } ?? "")
        }
    }
    static let major: Set<String> = ["SAFETY CAR","VSC","RED FLAG","SUSPENDED","RESTART","PENALTY","CAR STOPPED","RETIRED","MECHANICAL","INVESTIGATION","FASTEST LAP"]
}

enum StartPhase: String { case preGrid, formationLap, gridForming, startLights, lightsOut, race }
struct RaceStartPresentation {
    var factualAnchor: Date?
    func lightState(at date:Date)->StartLightTimeline.State? {
        if phase == .startLights,let illuminated,visible(at:date) {return .init(illuminated:illuminated,opacity:1)}
        guard let anchor=startedAt ?? factualAnchor else {
            if phase == .startLights,let illuminated,visible(at:date) {return .init(illuminated:illuminated,opacity:1)}
            return nil
        }
        if startedAt == nil,let sourceTime,sourceTime>anchor {return nil}
        return StartLightTimeline(anchor:anchor,source:startedAt == nil ? .firstLapStart:.explicitStart).state(at:date)
    }
    private(set) var phase: StartPhase = .preGrid
    private(set) var illuminated: Int?
    private(set) var sourceTime: Date?
    private(set) var startedAt: Date?
    var hasStarted: Bool {startedAt != nil || phase == .race}
    var suppressGaps: Bool { !hasStarted }
    mutating func observeCompletedRaceLap(at date: Date) {if !hasStarted {phase = .race;sourceTime=date}}
    mutating func ingest(message: String = "", lightCount: Int?, confirmedStart: Bool, at date: Date) {
        if let sourceTime, date < sourceTime { return }
        let m=message.uppercased()
        if m == "FORMATION LAP" || m == "EXTRA FORMATION LAP" || m.contains("FORMATION LAP STARTED") {phase = .formationLap;sourceTime=date;startedAt=nil;illuminated=nil}
        if m == "STANDING START" {phase = .startLights;sourceTime=date;startedAt=nil;illuminated=nil}
        if startedAt == nil {
            if m.contains("GRID FORMING") || m.contains("CARS TAKING GRID POSITIONS") {phase = .gridForming;sourceTime=date}
            if m == "START LIGHTS" {phase = .startLights;sourceTime=date}
            if let count=lightCount,(0...5).contains(count) {
                let previouslyLit=illuminated ?? 0
                illuminated=count;sourceTime=date;phase = .startLights
                if count==0 && previouslyLit>0 {startedAt=date;phase = .lightsOut}
            }
        }
        if confirmedStart && startedAt == nil {illuminated=nil;sourceTime=date;startedAt=date;phase = .lightsOut}
    }
    mutating func advance(at now: Date) {
        if startedAt == nil,let anchor=factualAnchor,now>=anchor,(sourceTime == nil || sourceTime!<=anchor) {startedAt=anchor;phase = .lightsOut;illuminated=0}
        if let startedAt,now.timeIntervalSince(startedAt)>=5 {phase = .race}
    }
    func visible(at now:Date)->Bool {
        if let startedAt {return now>=startedAt && now.timeIntervalSince(startedAt)<5}
        if phase == .formationLap || phase == .gridForming {return true}
        return phase == .startLights && sourceTime.map{now >= $0 && now.timeIntervalSince($0)<30} == true
    }
}
