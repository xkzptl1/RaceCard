import Foundation
import Observation
import RaceCardDataKit

@MainActor @Observable final class RaceStateStore {
    var session: SessionState?
    var drivers: [Int: DriverState] = [:]
    var events: [FeedEvent] = []
    var stewardEvents:[StewardEvent] = []
    var lapHistory:[Int:[Int:LapState]] = [:]
    var lapDeletions:[LapTimeDeletionEvent] = []
    var weather: WeatherState?
    var championship = ChampionshipState()
    var raceControl = RaceControlState()
    var raceStart = RaceStartPresentation()
    var connection = ConnectionState()
    var track: [TrackLocationState] = []
    var positionDataUnavailable = false
    var positionDataMessage:String?
    var metadata: TrackMetadata?
    var isRebuilding = false
    var notices: [MapNotice] = []
    private var noticeKeys: [String:Date] = [:]
    func advanceNotices(at now: Date = Date()) {
        raceStart.advance(at:currentTime)
        if let first=notices.first,persistentPriority>first.priority {notices[0].shownAt=nil;return}
        if let first = notices.first,let shown = first.shownAt,now.timeIntervalSince(shown) >= first.duration { notices.removeFirst() }
        if !notices.isEmpty && notices[0].shownAt == nil { notices[0].shownAt = now }
    }
    func clearMovements() { for id in Array(drivers.keys) { drivers[id]?.positionDelta = 0; drivers[id]?.movementAt = nil } }

    var fastest: (driver: Int, lap: LapState)?
    var tyreChanges: [TyreChangeState] = []
    var tyreDiagnostics: Set<String> = []
    var latestPit: PitState?
    var suspensions:[SuspensionInterval] = []
    func pitState(_ d:DriverState)->CurrentPitState {
        guard d.pits.contains(where:{$0.contains(currentTime)}) else{return .outside}
        return raceControl.phase == .red ? .pitDuringSuspension:.normalPit
    }
    var official = false
    var selected: Int?
    var presentationSpeed:Double = 0
    var presentationUpdatedAt = Date()
    var positionSamples:[Int:[PositionSample]] = [:]
    func recordPositionSamples(_ records:[NormalizedRecord]) {
        for r in records where r.kind == "location" {
            guard let id=r.driver,let x=r.fields.n("x"),let y=r.fields.n("y"),x != 0 || y != 0 else {continue}
            var samples=positionSamples[id] ?? []
            if !samples.contains(where:{$0.time==r.date}) {samples.append(.init(time:r.date,position:.init(x:x,y:y)))}
            samples.sort{$0.time<$1.time};positionSamples[id]=Array(samples.suffix(120))
        }
    }
    func displayPosition(_ driver:DriverState,at now:Date)->Coordinate? {
        let time=currentTime.addingTimeInterval(mode == .live ? -0.2 : min(0.25,max(0,now.timeIntervalSince(presentationUpdatedAt)))*presentationSpeed)
        return PositionInterpolator.position(at:time,samples:positionSamples[driver.id] ?? []) ?? driver.location.map{Coordinate(x:$0.x,y:$0.y)}
    }
    var currentTime = Date() {didSet {presentationUpdatedAt=Date()}}
    var mode: Mode = .mock
    private var ledger = RecordLedger()
    private var latest: [String: Date] = [:]
    private var streamOrder: [String: Int64] = [:]
    private var pendingDriverRecords: [Int:[NormalizedRecord]] = [:]
    private var stintRecordDates: [Int:[Int:Date]] = [:]
    private var traces: [Int: [TrackLocationState]] = [:]
    var leaderboard: [DriverState] { drivers.values.sorted { (displayPosition($0) ?? 999, $0.id) < (displayPosition($1) ?? 999, $1.id) } }
    func displayPosition(_ d: DriverState) -> Int? {
        if official {return d.position}
        if d.pitStart && (!raceStart.hasStarted || d.positionAt == nil || (raceStart.startedAt != nil && d.positionAt! < raceStart.startedAt!)) {return nil}
        return d.position ?? (!raceStart.hasStarted ? d.gridPosition : nil)
    }
    func waitingForPosition(_ d: DriverState) -> Bool { raceStart.hasStarted && displayPosition(d) == nil }
    var persistentNotice: MapNotice? {
        switch raceControl.phase {
        case .red: return .init(id:"persistent-red",category:"RED FLAG",text:"赤旗・セッション中断")
        case .safetyCar: return .init(id:"persistent-sc",category:"SAFETY CAR",text:"セーフティカー導入")
        case .virtualSafetyCar: return .init(id:"persistent-vsc",category:"VSC",text:"バーチャルセーフティカー導入")
        default:return nil
        }
    }
    private var startContextPriority:Int { [.formationLap,.gridForming].contains(raceStart.phase) ? 65 : 0 }
    private var persistentPriority:Int {max(persistentNotice?.priority ?? 0,startContextPriority)}
    var safetyEnding:Bool {
        guard let event=events.first(where:{$0.category == (raceControl.phase == .safetyCar ? "SAFETY CAR":"VSC")}) else{return false}
        let message=(event.rawMessage ?? "").uppercased()
        return message.contains("IN THIS LAP") || message.contains("ENDING")
    }
    var visibleNotice: MapNotice? {
        // Reconstruct the event overlay from factual cursor time, including seeks.
        events.filter { event in
            JapaneseRaceText.major.contains(event.category) && currentTime >= event.date && currentTime.timeIntervalSince(event.date)<5
        }.map { event in
            MapNotice(id:event.id,category:event.category,text:event.text,shownAt:event.date,driver:event.driverNumbers.first,event:event)
        }.max { $0.priority < $1.priority }
    }
    var lap: Int { drivers.values.map(\.currentLap).max() ?? 0 }
    func reset(_ session: SessionState, mode: Mode, preserveTrack: Bool = false) {
        stewardEvents=[];lapHistory=[:];lapDeletions=[];suspensions=[];positionDataUnavailable=false;positionDataMessage=nil;positionSamples=[:]
        pendingDriverRecords = [:]; stintRecordDates = [:]; tyreChanges = [];tyreDiagnostics=[]
        self.session = session; self.mode = mode; selected = nil; notices = []; noticeKeys = [:]; metadata = mode == .mock ? .fixture : TrackMetadata.load(circuit:session.circuit,session:session.id); drivers = [:]; events = []; weather = nil; championship = .init(); raceControl = .init(); raceStart = .init(); fastest = nil; latestPit = nil; official = false; ledger = .init(); latest = [:]; streamOrder = [:]; traces = [:]; if !preserveTrack { track = [] }; currentTime = session.start
    }
    func ingest(_ records: [NormalizedRecord], through cursor: Date? = nil) {
        let positions = drivers.mapValues { $0.position }; let acceptedAt = Date()
        for r in records.filter({cursor == nil || $0.date <= cursor!}).sorted(by: { a,b in
            if a.date == b.date { return (a.kind == "drivers" ? 0 : 1,a.order ?? 0) < (b.kind == "drivers" ? 0 : 1,b.order ?? 0) }; return a.date < b.date
        }) { apply(r) }
        if !isRebuilding && mode != .historical {
            for id in Array(drivers.keys) { guard var d = drivers[id],let old = positions[id] ?? nil,let new = d.position,old != new else { continue }; d.previousPosition = old; d.positionDelta = old-new; d.movementAt = acceptedAt; drivers[id] = d }
        }
    }
    func apply(_ r: NormalizedRecord) {
        let f = r.fields
        if let id=r.driver,drivers[id] == nil,["position","starting_grid","intervals","stints","pit","laps","location","car_data","session_result"].contains(r.kind) {
            pendingDriverRecords[id,default:[]].append(r);return
        }
        // Source time wins over delivery order, including reconnect batches.
        let entity = r.kind == "laps" ? String(f.i("lap_number") ?? 0) : r.kind == "stints" ? String(f.i("stint_number") ?? 1) : r.kind == "pit" ? r.id : ""
        let key = "\(r.kind):\(r.driver ?? 0):\(entity)"
        if r.kind != "race_control" {
            if let old=latest[key],r.date < old {return}
            if latest[key] == r.date,let order=r.order,let old=streamOrder[key],order <= old {return}
            latest[key]=r.date;if let order=r.order {streamOrder[key]=order}
        }
        if !["location","car_data","position","intervals","weather"].contains(r.kind) && !ledger.accept(r) {return}
        if r.kind == "drivers", let id = r.driver {
            var d = drivers[id] ?? DriverState(id: id, name: "", acronym: String(id), team: "", color: "888888")
            d.name = f.s("full_name") ?? d.name; d.familyName = f.s("last_name"); d.headshotURL = f.s("headshot_url"); d.acronym = f.s("name_acronym") ?? d.acronym; d.team = f.s("team_name") ?? d.team; d.color = f.s("team_colour") ?? d.color; drivers[id] = d; if let index = championship.drivers.firstIndex(where: { $0.id == String(id) }) { championship.drivers[index].name = d.acronym }
            // Keep early facts without adding non-participants from grid-only records.
            let pending=pendingDriverRecords.removeValue(forKey:id) ?? []
            for record in pending.sorted(by:{$0.date < $1.date}) {apply(record)}
            if var resolved=drivers[id] {
                resolved.stewardItems=StewardTimeline.active(stewardEvents,driver:id,at:max(currentTime,stewardEvents.map(\.timestamp).max() ?? r.date))
                if !official {resolved.investigation=resolved.stewardItems.contains{$0.state == .investigation};resolved.penalty=resolved.stewardItems.first?.penalty?.compact}
                drivers[id]=resolved
            }
            for index in events.indices where events[index].driverNumbers.contains(id) {
                let people=events[index].driverNumbers.compactMap{drivers[$0]}
                events[index].facts?.names=people.map(\.name);events[index].facts?.japaneseNames=people.map(DriverNameResolver.japanese)
            }
            return
        }
        if r.kind == "sessions", var updated = OpenF1Mapper.session(f) { updated.title = session?.title ?? updated.title; updated.totalLaps = session?.totalLaps; session = updated; return }
        if r.kind == "weather" { weather = WeatherState(air: f.n("air_temperature"),track: f.n("track_temperature"),rain: f.n("rainfall"),humidity: f.n("humidity"),wind: f.n("wind_speed")); return }
        if r.kind.hasPrefix("championship_") {
            let name = r.driver.flatMap { drivers[$0]?.acronym } ?? r.driver.map { "#\($0)" } ?? f.s("team_name") ?? ""
            let e = ChampionshipEntry(id: r.driver.map(String.init) ?? name, name: name, before: f.n("points_start") ?? 0, current: f.n("points_current") ?? 0, rankBefore: f.i("position_start") ?? 99, rankCurrent: f.i("position_current") ?? 99)
            if r.kind == "championship_drivers" { championship.drivers.removeAll { $0.id == e.id }; championship.drivers.append(e) } else { championship.teams.removeAll { $0.id == e.id }; championship.teams.append(e) }; return
        }
        if r.kind == "race_control" {
            let message = f.s("message") ?? ""; var flag = f.s("flag") ?? ""
            if let deletion=LapTimeDeletionEvent.normalize(r) {
                lapDeletions.append(deletion);refreshLapEligibility()
                event(r,deletion.reinstated ? "LAP TIME REINSTATED":"LAP TIME DELETED",deletion.text("ja",name:drivers[deletion.driverID].map(DriverNameResolver.japanese) ?? "\(deletion.driverID)号車"),raw:message)
                return
            }
            let steward=StewardEvent.normalize(r)
            let classified = steward.map { $0.state == .investigation ? "INVESTIGATION" : $0.state == .penalty ? "PENALTY" : $0.state == .noFurtherAction ? "NO FURTHER ACTION" : $0.state == .warning ? "WARNING" : $0.state == .reprimand ? "REPRIMAND" : $0.state == .cleared ? "PENALTY SERVED" : "RACE CONTROL" } ?? (f.s("scope") == "TimingSector" && flag == "RED" ? "SECTOR RED" : EventNormalizer.classification(message, flag: flag))
            // A cleared track does not end a suspended session. It completes a
            // factual SC/VSC ending sequence only; resumption needs its own event.
            let category = (classified == "SESSION START" && raceControl.phase == .red) || (classified == "TRACK CLEAR" && [.safetyCar,.virtualSafetyCar].contains(raceControl.phase) && safetyEnding) ? "RESTART" : classified
            if let steward {stewardEvents.removeAll{$0.id==steward.id};stewardEvents.append(steward)}
            raceStart.ingest(message:message,lightCount:f.i("start_lights"),confirmedStart:classified == "SESSION START",at:r.date)
            let controlKey="control:" + (["SAFETY CAR","VSC","RED FLAG","SUSPENDED","GREEN","RESTART","SESSION START","SESSION END"].contains(category) ? "phase" : category.hasPrefix("DRS") ? "drs" : f.i("sector").map{"sector:\(f.s("scope") ?? "Sector"):\($0)"} ?? "general")
            let fresh = latest[controlKey].map{r.date >= $0} ?? true
            if fresh {
            if latest[controlKey] == r.date,r.order == nil,let sector=f.i("sector") {
                let prior=f.s("scope") == "TimingSector" ? raceControl.timingSectorFlags[sector]:raceControl.sectorFlags[sector]
                let rank:[String:Int]=["CLEAR":0,"GREEN":0,"YELLOW":1,"DOUBLE YELLOW":2,"RED":3]
                if let prior,(rank[prior] ?? 0)>(rank[flag] ?? 0) {flag=prior}
            }
            latest[controlKey]=r.date
            let previousPhase=raceControl.phase
            raceControl.message = message
            if !flag.isEmpty { raceControl.flag = flag; raceControl.sector = f.i("sector"); if f.s("scope") != "TimingSector",let sector = f.i("sector") { if flag == "CLEAR" || flag == "GREEN" { raceControl.sectorFlags.removeValue(forKey:sector) } else { raceControl.sectorFlags[sector] = flag } } }
            if f.s("scope") == "TimingSector",let sector=f.i("sector"),(1...3).contains(sector),!flag.isEmpty {
                if flag == "CLEAR" || flag == "GREEN" {raceControl.timingSectorFlags.removeValue(forKey:sector)} else {raceControl.timingSectorFlags[sector]=flag}
            }
            switch category {
            case "SAFETY CAR": raceControl.phase = .safetyCar
            case "VSC": raceControl.phase = .virtualSafetyCar
            case "RED FLAG", "SUSPENDED": raceControl.phase = .red
            case "GREEN", "RESTART", "SESSION START": raceControl.phase = .green; raceControl.sectorFlags = [:];raceControl.timingSectorFlags = [:]
            case "SESSION END": raceControl.phase = .finished; raceControl.sectorFlags = [:];raceControl.timingSectorFlags = [:]
            case "DRS ENABLED": raceControl.drsEnabled = true
            case "DRS DISABLED": raceControl.drsEnabled = false
            default: break
            }
            if previousPhase != .red && raceControl.phase == .red {suspensions.append(.init(start:r.date))}
            if previousPhase == .red && raceControl.phase != .red,let index=suspensions.indices.last {suspensions[index].end=r.date}
            for index in events.indices where events[index].category == "PIT" {
                if let pit=drivers.values.flatMap({$0.pits}).first(where:{$0.id==events[index].id}) {events[index].facts?.fields["includes_suspension"] = .bool(pit.intersects(suspensions))}
            }
            if previousPhase != raceControl.phase {notices.removeAll{["SAFETY CAR","VSC","RED FLAG","SUSPENDED"].contains($0.category)}}
            }
            let involved=steward?.drivers ?? Array(Set([r.driver].compactMap{$0}+JapaneseRaceText.driverIDs(message))).sorted()
            let name = involved.isEmpty ? nil : involved.map { id in drivers[id].map(DriverNameResolver.japanese) ?? "\(id)号車" }.joined(separator:"、")
            event(r,category,JapaneseRaceText.text(category:category,raw:message,driver:name,sector:f.i("sector")),raw:message)
            for id in involved {
                guard var d=drivers[id] else{continue}
                let driverKey="control-driver:\(id):" + (category.hasPrefix("PENALTY") ? "penalty" : category == "INVESTIGATION" ? "investigation" : category == "PIT START" ? "grid" : "status")
                if latest[driverKey].map({r.date < $0}) == true {
                    if steward != nil {d.stewardItems=StewardTimeline.active(stewardEvents,driver:id,at:max(currentTime,stewardEvents.map(\.timestamp).max() ?? r.date));d.investigation=d.stewardItems.contains{$0.state == .investigation};d.penalty=d.stewardItems.first?.penalty?.compact;drivers[id]=d}
                    continue
                };latest[driverKey]=r.date
                if category == "PIT START" {d.pitStart=true;d.gridPosition=nil}
                if category == "CAR STOPPED" { d.status = "STOPPED" }
                if category == "RETIRED" { d.status = "RETIRED" }
                if category == "PENALTY" { d.penalty = JapaneseRaceText.penalty(message.uppercased()) }
                if category == "INVESTIGATION" { d.investigation = message.contains("INVESTIGAT") && !message.contains("NO FURTHER") }
                if message.contains("PENALTY SERVED") || message.contains("PENALTY WITHDRAWN") { d.penalty = nil }
                if steward != nil {
                    d.stewardItems=StewardTimeline.active(stewardEvents,driver:id,at:max(currentTime,stewardEvents.map(\.timestamp).max() ?? r.date))
                    d.investigation=d.stewardItems.contains{$0.state == .investigation}
                    d.penalty=d.stewardItems.first?.penalty?.compact
                }
                drivers[id] = d
            }; return
        }
        // Position exchanges alone do not establish an on-track overtake.
        if r.kind == "overtakes" { return }
        guard let id = r.driver, var d = drivers[id] else { return }
        d.lastUpdate = max(d.lastUpdate ?? .distantPast, r.date)
        switch r.kind {
        case "position": if let position=f.i("position"),position>0 {d.position=position;d.positionAt=r.date; if raceStart.hasStarted && r.date >= (raceStart.startedAt ?? .distantPast) {d.pitStart=false}}
        case "starting_grid":
            if let position=f.i("position"),position>0 {d.gridPosition=position}
            if f.b("pit_lane_start") || ["PIT","PL","PIT LANE"].contains(f.s("position")?.uppercased() ?? "") {d.pitStart=true;d.gridPosition=nil}
        case "intervals": d.gap = Timing.gap(f["gap_to_leader"]); d.interval = Timing.gap(f["interval"])
        case "location":
            recordPositionSamples([r])
            if let x = f.n("x"), let y = f.n("y"), x != 0 || y != 0 { d.location = .init(x: x,y: y,date: r.date)
                if mode == .live && track.isEmpty { traces[id,default:[]].append(d.location!); if traces[id]!.count > 1500 { traces[id]!.removeFirst(traces[id]!.count-1500) } }
            }
        case "car_data": d.telemetry = .init(speed: f.i("speed"),gear: f.i("n_gear"),rpm: f.i("rpm"),throttle: f.i("throttle"),brake: f.i("brake"),drs: f.i("drs"),date: r.date)
        case "laps":
            let l = LapState(number: f.i("lap_number") ?? 0,duration: f.n("lap_duration"),sectors: (1...3).map { f.n("duration_sector_\($0)") },speeds: [f.n("i1_speed"),f.n("i2_speed"),f.n("st_speed")],segments: (1...3).map { f["segments_sector_\($0)"]?.array.compactMap(\.int) ?? [] },start: Dates.parse(f.s("date_start")) ?? r.date)
            if mode == .live && track.isEmpty, let duration = l.duration, duration > 0 { let path = (traces[id] ?? []).filter { $0.date >= l.start && $0.date <= l.start.addingTimeInterval(duration) }; if path.count > 100 { track = path; traces = [:] } }
            d.currentLap = max(d.currentLap,l.number); if l.duration != nil && l.number >= (d.lastLap?.number ?? 0) { d.lastLap = l }
            if let duration = l.duration, duration > 0 {
                if session?.isRace == true && l.number>0 {raceStart.observeCompletedRaceLap(at:r.date)}
                if session?.isQualifying != true || !f.b("is_pit_out_lap") {
                    lapHistory[id,default:[:]][l.number]=l
                    if lapIsValid(l,driver:id),duration < (fastest?.lap.duration ?? .infinity) { event(r,"FASTEST LAP","\(DriverNameResolver.japanese(d))が最速ラップ・\(Timing.lap(duration))・\(l.number)周目") }
                }
            }
        case "stints":
            guard let number=f.i("stint_number"),number>0 else {
                tyreDiagnostics.insert("driver \(id): stint withheld — missing factual stint number/start lap");return
            }
            let verifiedBoundary=(f.i("lap_start") ?? 0)>0
            guard verifiedBoundary || number==1 else {tyreDiagnostics.insert("driver \(id), stint \(number): transition withheld — missing factual start lap");return}
            let boundary=verifiedBoundary ? f.i("lap_start")! : 0
            if !verifiedBoundary {tyreDiagnostics.insert("driver \(id): initial compound known, usage withheld — missing start lap")}
            if f.b("_boundary_unresolved") {tyreDiagnostics.insert("driver \(id), stint \(number): transition withheld — no usable historical boundary time");return}
            let stint = StintState(id:number,compound:f.s("compound")?.uppercased() ?? "UNKNOWN",start:boundary,end:f.i("lap_end"),initialAge:f.i("tyre_age_at_start").flatMap{$0>=0 ? $0 : nil},boundaryVerified:verifiedBoundary)
            if let previous=d.stints.first(where:{$0.id==number}),previous.start != boundary {
                tyreDiagnostics.insert("driver \(id), stint \(number): conflicting start lap withheld");return
            }
            d.stints.removeAll { $0.id == stint.id }; d.stints.append(stint)
            stintRecordDates[id,default:[:]][stint.id]=min(stintRecordDates[id]?[stint.id] ?? r.date,r.date)
            if stint.boundaryVerified,stint.id == d.currentStint?.id {d.currentLap=max(d.currentLap,stint.start)}
            drivers[id] = d
            rebuildTyreTransitions(for:id)
        case "pit":
            let pitLap=f.i("lap_number") ?? d.currentLap
            let pit = PitState(id:"pit:\(id):\(pitLap):\(Dates.iso(r.date))",driver: id,lap:pitLap,date:r.date,stopDuration:f.n("stop_duration"),laneDuration:f.n("lane_duration"))
            d.pits.removeAll { $0.id == pit.id }; d.pits.append(pit); d.pits.sort{$0.date < $1.date}; if pit.date >= (latestPit?.date ?? .distantPast) {latestPit = pit}
            var pitRecord=r;pitRecord.id=pit.id
            event(pitRecord,"PIT","\(DriverNameResolver.japanese(d))がピットイン・\(pit.lap)周目" + (pit.stopDuration.map { String(format:"・停止 %.3f秒",$0) } ?? "") + (pit.laneDuration.map { String(format:"・ピットレーン %.3f秒",$0) } ?? ""))
            drivers[id]=d;rebuildTyreTransitions(for:id)
        case "session_result":
            official = true; d.stewardItems=StewardTimeline.active(stewardEvents,driver:id,at:max(currentTime,r.date));d.penalty=d.stewardItems.first?.penalty?.compact;d.investigation=d.stewardItems.contains{$0.state == .investigation}; d.position = f.i("position"); d.gap = Timing.gap(f["gap_to_leader"]); d.status = f.b("dsq") ? "DSQ" : f.b("dns") ? "DNS" : f.b("dnf") ? "DNF" : nil; d.currentLap = f.i("number_of_laps") ?? d.currentLap
        default: break
        }
        drivers[id] = d
        if r.kind == "laps" {refreshLapEligibility()}
    }
    private func rebuildTyreTransitions(for id:Int) {
        guard let d=drivers[id] else{return}
        events.removeAll{$0.category=="TYRE CHANGE" && $0.driverNumbers==[id]}
        tyreChanges.removeAll{$0.driver==id}
        let ordered=d.stints.sorted{($0.start,$0.id)<($1.start,$1.id)}
        guard ordered.count>1 else{return}
        for pair in zip(ordered,ordered.dropFirst()) {
            let old=pair.0,new=pair.1
            guard new.id == old.id+1,new.start>old.start,
                  TyreCompound(old.compound) != .unknown,TyreCompound(new.compound) != .unknown,
                  let boundaryDate=stintRecordDates[id]?[new.id] else {
                tyreDiagnostics.insert("driver \(id), stint \(new.id): transition withheld — missing adjacent stint, compound or boundary");continue
            }
            let pit=d.pits.filter{($0.lap==new.start-1 || $0.lap==new.start) && abs($0.date.timeIntervalSince(boundaryDate))<=180}.min{abs($0.date.timeIntervalSince(boundaryDate))<abs($1.date.timeIntervalSince(boundaryDate))}
            let date=max(boundaryDate,pit?.date ?? boundaryDate)
            let stable="tyre:\(id):\(new.start):\(old.compound.uppercased()):\(new.compound.uppercased())"
            let change=TyreChangeState(id:stable,driver:id,lap:new.start,date:date,fromCompound:old.compound.uppercased(),toCompound:new.compound.uppercased(),priorUsage:new.initialAge,pitRecordID:pit?.id,pitStopDuration:pit?.stopDuration)
            tyreChanges.append(change)
            let text="\(DriverNameResolver.japanese(d))：\(L10n.text(change.fromCompound,language:"ja")) → \(L10n.text(change.toCompound,language:"ja"))"
            let record=NormalizedRecord(id:stable,order:nil,date:date,kind:"tyre_change",driver:id,fields:["lap_number":.number(Double(new.start)),"from_compound":.string(change.fromCompound),"to_compound":.string(change.toCompound)])
            event(record,"TYRE CHANGE",text)
        }
        tyreChanges.sort{$0.date<$1.date}
    }
    func tyreValidationReport() -> String {
        var lines=["RaceCard tyre-change cross-validation", "driver\tlap\tfrom\tto\tstint boundary\tpit matched\tprior usage\tcurrent stint start\tstatus"]
        for c in tyreChanges.sorted(by:{$0.date<$1.date}) {
            let code=drivers[c.driver]?.acronym ?? String(c.driver)
            lines.append("\(code)\t\(c.lap)\t\(c.fromCompound)\t\(c.toCompound)\tL\(c.lap)\t\(c.pitRecordID == nil ? "no" : "yes")\t\(c.priorUsage.map(String.init) ?? "unknown")\tL\(c.lap)\t\(c.validationStatus)")
        }
        lines += ["", "Source ambiguities (withheld, never invented):"] + tyreDiagnostics.sorted()
        return lines.joined(separator:"\n")+"\n"
    }
    func status(_ d: DriverState) -> String? {
        if let status = d.status { return status }
        if pitState(d) == .normalPit { return "PIT" }
        if mode == .live, let update = d.lastUpdate, currentTime.timeIntervalSince(update) > 15 { return "STALE" }
        return nil
    }
    func lapIsValid(_ lap:LapState,driver:Int)->Bool {
        let decision=lapDeletions.filter{$0.driverID==driver && $0.matches(lap)}.max{$0.timestamp<$1.timestamp}
        return decision?.reinstated ?? true
    }
    private func refreshLapEligibility() {
        fastest=nil
        for (driver,laps) in lapHistory.sorted(by:{$0.key<$1.key}) {
            let best=laps.values.filter{$0.duration.map{$0>0} ?? false}.filter{lapIsValid($0,driver:driver)}.min{($0.duration!,$0.start)<($1.duration!,$1.start)}
            drivers[driver]?.bestLap=best
            if let best,best.duration! < (fastest?.lap.duration ?? .infinity) {fastest=(driver,best)}
        }
        for index in events.indices where events[index].category=="FASTEST LAP" {
            if let driver=events[index].driverNumbers.first,let number=events[index].facts?.fields.i("lap_number"),let lap=lapHistory[driver]?[number] {events[index].facts?.fields["invalidated"] = .bool(!lapIsValid(lap,driver:driver))}
        }
    }
    private func event(_ r: NormalizedRecord, _ category: String, _ text: String, raw: String? = nil) {
        var e = FeedEvent(id: r.id,order: r.order,date: r.date,lap: r.fields.i("lap_number"),category: category,text: text,rawMessage:raw,driverNumbers:Array(Set([r.driver].compactMap{$0} + JapaneseRaceText.driverIDs(raw ?? ""))).sorted())
        e.deletion=LapTimeDeletionEvent.normalize(r)
        if let deletion=e.deletion {e.driverNumbers=[deletion.driverID];e.lap=deletion.lapNumber ?? deletion.sourceLapNumber}
        e.steward=StewardEvent.normalize(r)
        if let steward=e.steward {e.driverNumbers=steward.drivers}
        let people=e.driverNumbers.compactMap{drivers[$0]}
        e.facts = .init(fields:r.fields,names:people.map(\.name),japaneseNames:people.map(DriverNameResolver.japanese))
        if category == "PIT",let pit=latestPit,pit.id==e.id {e.facts?.fields["includes_suspension"] = .bool(pit.intersects(suspensions))}
        events.removeAll { $0.id == e.id || (e.deletion == nil && $0.deletion == nil && e.steward == nil && $0.steward == nil && $0.category == category && $0.text == text && abs($0.date.timeIntervalSince(e.date)) < 2) }
        events.append(e); events.sort { a,b in a.date == b.date ? (a.order ?? 0) > (b.order ?? 0) : a.date > b.date }
        if !isRebuilding && mode != .historical && JapaneseRaceText.major.contains(category) && r.date >= currentTime.addingTimeInterval(-10) {
            let key = category + ":" + text
            if noticeKeys[key].map({ abs(r.date.timeIntervalSince($0)) > 30 }) ?? true {
                noticeKeys[key] = r.date
                notices.append(.init(id:r.id,category:category,text:text,driver:r.driver,event:e))
                notices.sort{$0.priority > $1.priority}; for i in notices.indices.dropFirst(){notices[i].shownAt=nil}; if notices.count > 8 {notices.removeLast()}; advanceNotices()
            }
        }
    }
}
