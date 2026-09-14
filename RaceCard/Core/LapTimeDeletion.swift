import Foundation

struct LapTimeDeletionEvent:Codable,Equatable {
    let driverID:Int
    let lapNumber:Int?
    let sourceLapNumber:Int?
    let deletedLapTime:Double?
    let reason:String?
    let sourceReason:String?
    let turn:Int?
    let sector:Int?
    let rawMessage:String
    let timestamp:Date
    let reinstated:Bool
    static func normalize(_ r:NormalizedRecord)->Self? {
        let raw=r.fields.s("message") ?? "",m=raw.uppercased()
        guard (m.contains("TIME") || m.contains("LAP DELETED") || m.contains("LAP REINSTATED")),(m.contains("DELETED") || m.contains("REINSTATED")),let driver=r.driver ?? r.fields.i("driver_number") ?? JapaneseRaceText.driverID(m) else{return nil}
        let value=JapaneseRaceText.capture(#"(?:LAP\s+)?TIME\s+(\d+:\d{2}\.\d+)"#,m)?.first
        let parts=value?.split(separator:":").compactMap{Double($0)}
        let duration=parts.flatMap{$0.count==2 ? $0[0]*60+$0[1]:nil}
        let clause=raw.range(of:" - ").map{String(raw[$0.upperBound...])}
        let code:String?
        if let c=clause?.uppercased() {
            code=c.contains("TRACK LIMIT") ? "trackLimits":c.contains("YELLOW") ? "yellowFlag":c.contains("SHORTCUT") || c.contains("GAINING AN ADVANTAGE") ? "advantage":c.contains("LEAVING THE TRACK") ? "leavingTrack":"other"
        } else {code=nil}
        return .init(driverID:driver,lapNumber:JapaneseRaceText.capture(#"\bLAP\s+(\d+)\b"#,m)?.first.flatMap(Int.init),sourceLapNumber:r.fields.i("lap_number"),deletedLapTime:duration,reason:code,sourceReason:clause,turn:JapaneseRaceText.capture(#"\bTURN\s+(\d+)\b"#,m)?.first.flatMap(Int.init),sector:r.fields.i("sector"),rawMessage:raw,timestamp:r.date,reinstated:m.contains("REINSTATED"))
    }
    func text(_ language:String,name:String)->String {
        let ja=language=="ja"
        let reasons=["trackLimits":("Track limits","トラックリミット違反"),"yellowFlag":("Yellow-flag invalidation","黄旗によるタイム無効"),"advantage":("Shortcut / gaining an advantage","ショートカット・利益を得た走行"),"leavingTrack":("Leaving the track","コース外走行")]
        let why=reason.flatMap{reasons[$0]}.map{ja ? $0.1:$0.0} ?? (sourceReason ?? (ja ? "理由未提供":"Reason not provided"))
        let title=ja ? name+(reinstated ? "のラップタイム復活":"のラップタイム抹消"):name+(reinstated ? " lap time reinstated":" lap time deleted")
        return title+"\n"+([deletedLapTime.map{Timing.lap($0)},why,turn.map{"T\($0)"},lapNumber.map{ja ? "\($0)周目":"Lap \($0)"}].compactMap{$0}.joined(separator:" · "))
    }
    func matches(_ lap:LapState)->Bool {
        if let deletedLapTime,let duration=lap.duration {return abs(deletedLapTime-duration)<0.0005}
        if let lapNumber {return lap.number==lapNumber}
        return false
    }
}
