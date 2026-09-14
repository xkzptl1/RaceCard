import Foundation

/// Source facts remain language independent; the same event can be rendered again after a language change.
struct RaceEventFacts: Codable, Equatable {
    var fields: [String:JSONValue]
    var names: [String]
    var japaneseNames: [String]
    func text(category:String,raw:String?,language:String)->String {
        let ja=language == "ja", who=(ja ? japaneseNames:names).joined(separator:ja ? "、":", ")
        let lap=fields.i("lap_number") ?? 0
        switch category {
        case "BLACK & WHITE FLAG":return (ja ? "\(who)に黒白旗":"Black & white flag for \(who)")+"\n"+((raw?.uppercased().contains("TRACK LIMIT") ?? false) ? (ja ? "トラックリミット違反":"Track limits"):(raw ?? ""))
        case "FASTEST LAP":
            if fields.b("invalidated") {return ja ? "\(who)の旧最速ラップは抹消 · \(Timing.lap(fields.n("lap_duration")))":"\(who) · previous fastest lap deleted · \(Timing.lap(fields.n("lap_duration")))"}
            return ja ? "\(who)が最速ラップ・\(Timing.lap(fields.n("lap_duration")))・\(lap)周目" : "\(who) · fastest lap \(Timing.lap(fields.n("lap_duration"))) · Lap \(lap)"
        case "PIT":
            let timing=PitTimingPresentation(stopDuration:fields.n("stop_duration"),laneDuration:fields.n("lane_duration"),suspended:fields.b("includes_suspension"))
            let heading=timing.suspended ? (ja ? "\(who)がピットレーンへ · \(lap)周目":"\(who) enters the pit lane · Lap \(lap)") : (ja ? "\(who)がピットイン · \(lap)周目":"\(who) pits · Lap \(lap)")
            return heading+"\n"+timing.primary(language)+(!timing.suspended ? timing.occupancy(language).map{" · "+$0} ?? "":"")
        case "TYRE CHANGE": return who+" · "+L10n.text(fields.s("from_compound") ?? "UNKNOWN",language:language)+" → "+L10n.text(fields.s("to_compound") ?? "UNKNOWN",language:language)
        default:
            if ja {return JapaneseRaceText.text(category:category,raw:raw ?? "",driver:who.isEmpty ? nil:who,sector:fields.i("sector"))}
            // Official race-control source text is English and retained verbatim, never reverse-translated.
            if let raw,!raw.isEmpty {return raw}
            return L10n.text(category,language:language)
        }
    }
}
extension FeedEvent {
    func localizedText(_ language:String)->String {if let deletion {return deletion.text(language,name:(language == "ja" ? facts?.japaneseNames:facts?.names)?.joined(separator:", ") ?? "#\(deletion.driverID)")};if let steward {return steward.text(language,driverName:(language == "ja" ? facts?.japaneseNames:facts?.names)?.joined(separator:language == "ja" ? "、":", "))};return facts?.text(category:category,raw:rawMessage,language:language) ?? (language == "en" ? rawMessage ?? category:text)}
}
enum CurrentPitState:Equatable {case outside, normalPit, pitDuringSuspension}
struct SuspensionInterval:Equatable {var start:Date;var end:Date?}
extension PitState {
    var exit:Date? {return pitExitTimestamp}
    func contains(_ cursor:Date)->Bool {guard let exit else{return false};return date<=cursor && cursor<exit}
    func intersects(_ intervals:[SuspensionInterval])->Bool {guard let exit else{return false};return intervals.contains{$0.start<exit && ($0.end ?? .distantFuture)>date}}
}
extension TelemetryState {
    static let freshness:TimeInterval=3
    func valid(at cursor:Date)->Bool {date<=cursor && cursor.timeIntervalSince(date)<=Self.freshness}
    static func resolve(_ records:[NormalizedRecord],driver:Int,at cursor:Date)->Self? {
        guard let r=records.filter({$0.kind=="car_data" && $0.driver==driver && $0.date<=cursor}).max(by:{$0.date<$1.date}) else{return nil}
        let f=r.fields,t=Self(speed:f.i("speed"),gear:f.i("n_gear"),rpm:f.i("rpm"),throttle:f.i("throttle"),brake:f.i("brake"),drs:f.i("drs"),date:r.date)
        return t.valid(at:cursor) ? t:nil
    }
}

struct StintHistoryRow:Identifiable,Equatable {
    var id:Int;var start:Int?;var end:Int?;var compound:String;var raceLaps:Int?;var prior:Int?;var current:Bool
    var range:String {guard let start else{return "—"};return "L\(start)–"+(end.map(String.init) ?? "")}
    static func rows(_ driver:DriverState)->[Self] {
        let stints=driver.stints.sorted{($0.start,$0.id)<($1.start,$1.id)}
        return stints.enumerated().map {index,stint in
            let next=index+1<stints.count ? stints[index+1]:nil
            // Completed timing is the source of truth. A started lap is not a completed lap.
            let completed=driver.lastLap?.number ?? 0
            let finished=next != nil || (stint.end.map{completed >= $0} ?? false)
            let end=finished ? (stint.end.flatMap{$0<=completed || next != nil ? $0:nil} ?? next.flatMap{$0.boundaryVerified ? $0.start-1:nil}):nil
            let laps:Int?=stint.boundaryVerified ? max(0,min(completed,end ?? completed)-stint.start+1):nil
            return .init(id:stint.id,start:stint.boundaryVerified ? stint.start:nil,end:end,compound:stint.compound,raceLaps:laps,prior:stint.initialAge,current:!finished && next == nil)
        }
    }
}

/// Display semantics never mutate or estimate provider values.
struct PitTimingPresentation {
    let stopDuration:Double?;let laneDuration:Double?;let suspended:Bool
    func service(_ language:String)->String {
        stopDuration.flatMap{$0.isFinite && $0>=0 ? $0:nil}.map{String(format:language == "ja" ? "停止 %.3f秒":"Stop %.3fs",$0)} ?? (language == "ja" ? "停止時間 不明":"Stop time unavailable")
    }
    func primary(_ language:String)->String {
        service(language)+(suspended ? (language == "ja" ? " · 赤旗中断中":" · During red-flag suspension"):"")
    }
    func occupancy(_ language:String)->String? {
        guard let laneDuration,laneDuration.isFinite,laneDuration>=0 else{return nil}
        let ja=language == "ja"
        let duration=suspended ? String(format:"%d:%06.3f",Int(laneDuration)/60,laneDuration.truncatingRemainder(dividingBy:60)) : String(format:ja ? "%.3f秒":"%.3fs",laneDuration)
        return (ja ? "ピットレーン滞在 ":"Pit-lane duration ")+duration
    }
    func detail(_ language:String)->String {
        primary(language)+(occupancy(language).map{"\n"+$0} ?? "")+(suspended && occupancy(language) != nil ? (language == "ja" ? "\n赤旗・セッション中断時間を含む":"\nIncludes Red Flag / session suspension time"):"")
    }
    static func fastest(_ pits:[PitState])->PitState? {pits.filter{$0.stopDuration.map{$0.isFinite && $0>=0} ?? false}.min{$0.stopDuration!<$1.stopDuration!}}
}
extension FeedEvent {
    func localizedDetail(_ language:String)->String {
        guard category=="PIT",let f=facts?.fields else{return localizedText(language)+(rawMessage.map{"\n"+$0} ?? "")}
        return localizedText(language).components(separatedBy:"\n").first!+"\n"+PitTimingPresentation(stopDuration:f.n("stop_duration"),laneDuration:f.n("lane_duration"),suspended:f.b("includes_suspension")).detail(language)
    }
}
