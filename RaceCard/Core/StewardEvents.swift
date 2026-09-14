import Foundation

enum StewardState:String,Codable {case investigation,noted,penalty,noFurtherAction,warning,reprimand,cleared,other}
enum StewardPenalty:Codable,Equatable {
    case time(Int),driveThrough,stopGo,grid(Int),warning,reprimand,disqualified
    var compact:String {switch self {case .time(let n):return "+\(n)s";case .driveThrough:return "DT";case .stopGo:return "SG";case .grid(let n):return "G+\(n)";case .warning:return "WARN";case .reprimand:return "REP";case .disqualified:return "DSQ"}}
    var priority:Int {switch self {case .disqualified:return 100;case .stopGo:return 90;case .driveThrough:return 80;case .time:return 70;case .grid:return 65;case .warning,.reprimand:return 30}}
    func title(_ language:String)->String {let ja=language=="ja";switch self {
    case .time(let n):return ja ? "\(n)秒加算ペナルティ":"\(n)-second time penalty"
    case .driveThrough:return ja ? "ドライブスルーペナルティ":"Drive-through penalty"
    case .stopGo:return ja ? "ストップ＆ゴーペナルティ":"Stop-and-go penalty"
    case .grid(let n):return ja ? "\(n)グリッド降格":"\(n)-place grid penalty"
    case .warning:return ja ? "警告":"Warning"
    case .reprimand:return ja ? "戒告":"Reprimand"
    case .disqualified:return ja ? "失格":"Disqualification"
    }}
}
struct StewardReason:Codable,Equatable {
    var code:String;var source:String
    static func parse(_ raw:String)->Self? {
        guard let split=raw.range(of:" - ") ?? raw.range(of:" – ") else{return nil}
        let clause=String(raw[split.upperBound...]).trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clause.isEmpty else{return nil}
        let upper=clause.uppercased()
        if upper.range(of:#"^\d+\s+(?:SECOND|SEC)\s+(?:TIME\s+)?PENALTY\s*$"#,options:.regularExpression) != nil {return nil}
        let known:[(String,String)]=[("CAUSING A COLLISION","collision"),("TRACK LIMITS","trackLimits"),("UNSAFE RELEASE","unsafeRelease"),("IMPEDING","impeding"),("FORCING ANOTHER DRIVER OFF","forcingOff"),("LEAVING THE TRACK AND GAINING","advantage"),("PIT LANE SPEED","pitSpeed"),("SPEEDING IN THE PIT","pitSpeed"),("YELLOW FLAG INFRINGEMENT","yellowFlag"),("PRACTICE START INFRINGEMENT","practiceStart"),("STARTING PROCEDURE INFRINGEMENT","startingProcedure"),("ESCAPE ROAD INSTRUCTIONS","escapeRoad"),("FALSE START","falseStart"),("JUMP START","falseStart")]
        return .init(code:known.first{upper.contains($0.0)}?.1 ?? "other",source:clause)
    }
    var fingerprint:String {source.uppercased().replacingOccurrences(of:#"\s*\([0-9:]+\)"#,with:"",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)}
    func text(_ language:String,alleged:Bool)->String {
        let ja=language=="ja"
        let translations:[String:(String,String)]=["collision":("Causing a collision","接触を引き起こした行為"),"trackLimits":("Track limits infringement","トラックリミット違反"),"unsafeRelease":("Unsafe release","危険なピットリリース"),"impeding":("Impeding another driver","他車の走行妨害"),"forcingOff":("Forcing another driver off track","他車をコース外へ押し出した行為"),"advantage":("Leaving the track and gaining an advantage","コース外走行による利益"),"pitSpeed":("Pit-lane speeding","ピットレーン速度違反"),"yellowFlag":("Yellow flag infringement","黄旗規定違反"),"practiceStart":("Practice start infringement","練習スタート規定違反"),"startingProcedure":("Starting procedure infringement","スタート手順違反"),"escapeRoad":("Failure to follow escape-road instructions","エスケープロード指示違反"),"falseStart":("False start","フライングスタート")]
        guard let wording=translations[code] else{return ja ? "理由の詳細は公式原文を参照":"See official source for reason"}
        return ja ? wording.1+(alleged ? "の可能性":"") : (alleged ? "Alleged ":"")+wording.0.prefix(1).lowercased()+wording.0.dropFirst()
    }
}
struct StewardEvent:Identifiable,Codable,Equatable {
    var id:String;var drivers:[Int];var lap:Int?;var state:StewardState;var reason:StewardReason?;var penalty:StewardPenalty?;var rawMessage:String;var timestamp:Date;var incidentTime:String?;var turn:Int?;var afterRace=false;var incidentID:String?;var initialAllegation:StewardReason?;var initialTimestamp:Date?
    var priority:Int {penalty?.priority ?? (state == .investigation ? 50:10)}
    var compact:String? {penalty?.compact ?? (state == .investigation ? (afterRace ? "POST":"INV"):nil)}
    static func normalize(_ r:NormalizedRecord)->Self? {
        let raw=r.fields.s("message") ?? "",m=raw.uppercased()
        guard LapTimeDeletionEvent.normalize(r) == nil else{return nil}
        let ids=Array(Set([r.driver,r.fields.i("driver_number")].compactMap{$0}+JapaneseRaceText.driverIDs(m))).sorted()
        guard !ids.isEmpty else{return nil}
        var state:StewardState;var penalty:StewardPenalty?
        if m.contains("NO FURTHER ACTION") || m.contains("NO FURTHER INVESTIGATION") {state = .noFurtherAction}
        else if m.contains("PENALTY SERVED") || m.contains("PENALTY WITHDRAWN") || m.contains("INVESTIGATION CLOSED") {state = .cleared}
        else if m.contains("UNDER INVESTIGATION") || m.contains("WILL BE INVESTIGATED") {state = .investigation}
        else if m.contains("NOTED") {state = .noted}
        else if m.contains("DISQUALIFIED") || m.contains("DISQUALIFICATION FOR CAR") {state = .penalty;penalty = .disqualified}
        else if m.contains("DRIVE THROUGH") || m.contains("DRIVE-THROUGH") {state = .penalty;penalty = .driveThrough}
        else if m.contains("STOP GO") || m.contains("STOP-GO") || m.contains("STOP AND GO") || m.contains("STOP & GO") {state = .penalty;penalty = .stopGo}
        else if let value=JapaneseRaceText.capture(#"\b(\d+)\s*(?:SECOND|SEC|S)\s+(?:TIME\s+)?PENALTY"#,m)?.first.flatMap(Int.init) {state = .penalty;penalty = .time(value)}
        else if let value=JapaneseRaceText.capture(#"\b(\d+)[ -]+(?:PLACE|POSITION)[ -]+GRID PENALTY"#,m)?.first.flatMap(Int.init) {state = .penalty;penalty = .grid(value)}
        else if m.contains("REPRIMAND") {state = .reprimand;penalty = .reprimand}
        else if m.contains("WARNING") {state = .warning;penalty = .warning}
        else if m.contains("PENALTY") {state = .penalty}
        else {return nil}
        return .init(id:r.id,drivers:ids,lap:r.fields.i("lap_number"),state:state,reason:StewardReason.parse(raw),penalty:penalty,rawMessage:raw,timestamp:r.date,incidentTime:JapaneseRaceText.capture(#"\((\d{2}:\d{2}:\d{2})\)"#,m)?.first,turn:JapaneseRaceText.capture(#"TURN\s+(\d+)"#,m)?.first.flatMap(Int.init),afterRace:m.contains("AFTER THE RACE") || m.contains("AFTER RACE"),incidentID:r.fields.s("incident_id"))
    }
    func text(_ language:String,driverName:String?=nil)->String {
        let ja=language=="ja",name=driverName.flatMap{$0.isEmpty ? nil:$0} ?? drivers.map{ja ? "\($0)号車":"Car \($0)"}.joined(separator:ja ? "、":", ")
        let headline:String
        switch state {
        case .investigation:headline=afterRace ? (ja ? "\(name)はレース後に審議":"\(name) · investigation after the race") : (ja ? "\(name)が審議対象":"\(name) under investigation")
        case .noted:headline=ja ? "\(name)の事象を記録":"Incident noted for \(name)"
        case .noFurtherAction:headline=ja ? "\(name)への審議は処分なし":"No further action for \(name)"
        case .cleared:headline=ja ? "\(name)の処分・審議状態を解除":"Steward status cleared for \(name)"
        case .penalty,.warning,.reprimand:headline=ja ? "\(name)に\(penalty?.title(language) ?? "ペナルティ通知")":"\(name) · \(penalty?.title(language) ?? "Penalty notification")"
        case .other:headline=ja ? "スチュワード通知":"Steward notification"
        }
        let explanation=reason?.text(language,alleged:state == .investigation || state == .noted || state == .noFurtherAction) ?? (ja ? "理由未提供":"Reason not provided")
        let history=initialAllegation.flatMap {original in initialTimestamp != nil && original != reason ? "\n"+(ja ? "当初の疑い：":"Initial allegation: ")+original.text(language,alleged:true):nil} ?? ""
        return headline+"\n"+explanation+(lap.map{ja ? " · \($0)周目":" · Lap \($0)"} ?? "")+history
    }
}
enum StewardTimeline {
    static func active(_ events:[StewardEvent],driver:Int,at cursor:Date)->[StewardEvent] {
        var active:[StewardEvent]=[]
        for var e in events.filter({$0.timestamp<=cursor && $0.drivers.contains(driver)}).sorted(by:{($0.timestamp,$0.id)<($1.timestamp,$1.id)}) {
            func compatible(_ prior:StewardEvent)->Bool {
                if let a=e.incidentTime,let b=prior.incidentTime,a != b {return false}
                if let a=e.turn,let b=prior.turn,a != b {return false}
                if let a=e.incidentID,let b=prior.incidentID {return a==b}
                if let a=e.incidentTime,let b=prior.incidentTime,a==b {return true}
                if let a=e.reason,let b=prior.reason,a.fingerprint != b.fingerprint {return false}
                if e.reason != nil && prior.reason == nil {return false}
                if let a=e.incidentTime,let b=prior.incidentTime,a==b {return true}
                return e.timestamp.timeIntervalSince(prior.timestamp)<=3600 && (e.lap == nil || prior.lap == nil || abs(e.lap!-prior.lap!)<=20)
            }
            let pending=active.indices.filter{[StewardState.investigation,.noted].contains(active[$0].state) && compatible(active[$0])}
            switch e.state {
            case .investigation:
                let same=pending.filter {index in
                    let prior=active[index]
                    if prior.state == .noted {return true}
                    if let a=e.incidentTime,let b=prior.incidentTime {return a==b}
                    return e.reason != nil && prior.reason != nil && e.reason?.fingerprint==prior.reason?.fingerprint && e.lap==prior.lap && e.turn==prior.turn && e.timestamp.timeIntervalSince(prior.timestamp)<120
                }
                if same.count==1 {let old=active.remove(at:same[0]);e.initialAllegation=old.initialAllegation ?? old.reason;e.initialTimestamp=old.initialTimestamp ?? old.timestamp};active.append(e)
            case .noted:active.append(e)
            case .penalty,.warning,.reprimand,.noFurtherAction:
                // Resolve only one unambiguous compatible incident. Other investigations survive.
                if pending.count==1 {let old=active.remove(at:pending[0]);e.initialAllegation=old.initialAllegation ?? old.reason;e.initialTimestamp=old.initialTimestamp ?? old.timestamp}
                if e.state != .noFurtherAction {active.append(e)}
            case .cleared:
                let candidates=active.indices.filter{compatible(active[$0]) && (e.rawMessage.uppercased().contains("PENALTY") ? active[$0].penalty != nil:active[$0].state == .investigation)}
                if candidates.count==1 {active.remove(at:candidates[0])}
            case .other:break
            }
        }
        return active.sorted{($0.priority,$0.timestamp)>($1.priority,$1.timestamp)}
    }
}
