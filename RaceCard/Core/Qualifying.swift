import Foundation

extension SessionState {
    func qualifyingPhaseTitle(_ phase:Int)->String {(type=="Sprint Qualifying" ? "SQ":"Q")+String(phase)}
    var isQualifying:Bool { ["Qualifying","Sprint Qualifying"].contains(type) }
}
enum TimingMerit:String {case sessionBest,personalBest,neutral}
struct QualifyingSectorStroke {
    var number:Int;var points:[TrackPoint]
}
enum QualifyingMapTiming {
    /// Split the immutable recorded lap at verified timing boundaries, never at car positions.
    static func strokes(lap:[TrackPoint],boundaries:[Int:TrackPoint])->[QualifyingSectorStroke] {
        guard lap.count>10,let s1=boundaries[1],let s2=boundaries[2] else{return []}
        func nearest(_ point:TrackPoint)->Int {lap.indices.min {a,b in
            hypot(lap[a].x-point.x,lap[a].y-point.y)<hypot(lap[b].x-point.x,lap[b].y-point.y)
        }!}
        let a=nearest(s1),b=nearest(s2)
        guard a>0,b>a,b<lap.count-1 else{return []}
        return [.init(number:1,points:Array(lap[0...a])),.init(number:2,points:Array(lap[a...b])),.init(number:3,points:Array(lap[b...])+[lap[0]])]
    }
    static func emphasis(_ timing:QualifyingDriverTiming?,at cursor:Date)->[Int:TimingMerit] {
        guard let timing,let lap=timing.current,!lap.outLap,timing.state != "Lap Deleted",timing.state != "PIT" else{return [:]}
        var result:[Int:TimingMerit]=[:]
        for i in 0..<3 {
            guard timing.sectors[i] != nil,let completed=lap.completion(i),cursor>=completed,cursor.timeIntervalSince(completed)<8 else{continue}
            result[i+1]=timing.merits[i]
        }
        return result
    }
}
struct QualifyingLap:Identifiable {
    let driver:Int;let number:Int;let start:Date;let duration:Double?;let sectors:[Double?];let outLap:Bool
    var id:String {"\(driver)-\(number)"}
    var finish:Date? {duration.map{start.addingTimeInterval($0)}}
    var state:LapState {.init(number:number,duration:duration,sectors:sectors,speeds:[],segments:[],start:start)}
    func completion(_ index:Int)->Date? {
        let prefix=sectors.prefix(index+1)
        guard prefix.count==index+1,prefix.allSatisfy({$0 != nil}) else{return nil}
        return start.addingTimeInterval(prefix.compactMap{$0}.reduce(0,+))
    }
}
struct QualifyingPhase:Identifiable {let id:Int;let start:Date}
struct QualifyingRankMotion {
    private var previous:QualifyingSnapshot?
    private var changes:[Int:(delta:Int,date:Date)]=[:]
    mutating func update(_ next:QualifyingSnapshot,at now:Date,reset:Bool=false) {
        defer {previous=next}
        guard !reset,let old=previous,old.phase==next.phase else{changes=[:];return}
        for (index,id) in next.order.enumerated() {
            guard let before=old.order.firstIndex(of:id),before != index,
                  old.drivers[id]?.best != nil else{continue}
            changes[id]=(before-index,now)
        }
    }
    func movement(_ driver:Int,at now:Date)->Int {
        guard let change=changes[driver],now.timeIntervalSince(change.date)<4 else{return 0}
        return change.delta
    }
}
struct QualifyingDriverTiming {
    var driver:Int;var current:QualifyingLap?;var sectors:[Double?]=[nil,nil,nil]
    var merits:[TimingMerit]=[.neutral,.neutral,.neutral];var best:Double?;var phaseBests:[Int:Double]=[:]
    var delta:Double?;var elapsed:Double?;var state="No Time";var phase:Int?;var rankPhase:Int=0;var eliminated=false
}
/// Historical source records stay separate from published state. Every result below is rebuilt
/// from the replay cursor, including deletion decisions and individual sector completion times.
struct QualifyingTimeline {
    var cuts:[Int:Int]=[:]
    var laps:[QualifyingLap]=[];var phases:[QualifyingPhase]=[];var deletions:[LapTimeDeletionEvent]=[]
    init(records:[NormalizedRecord]=[]) {
        laps=records.filter{$0.kind=="laps"}.compactMap {r in
            guard let driver=r.driver,let number=r.fields.i("lap_number"),let start=Dates.parse(r.fields.s("date_start")),!r.fields.b("_inferred_lap_start") else{return nil}
            func positive(_ value:Double?)->Double? {value.flatMap{$0.isFinite && $0>0 ? $0:nil}}
            return .init(driver:driver,number:number,start:start,duration:positive(r.fields.n("lap_duration")),sectors:(1...3).map{positive(r.fields.n("duration_sector_\($0)"))},outLap:r.fields.b("is_pit_out_lap"))
        }.sorted{($0.start,$0.driver,$0.number)<($1.start,$1.driver,$1.number)}
        let starts=records.filter{$0.kind=="race_control" && $0.fields.s("message")=="SESSION STARTED" && $0.fields.i("qualifying_phase") != nil}
        phases=Dictionary(grouping:starts,by:{$0.fields.i("qualifying_phase")!}).compactMap {id,rows in rows.map(\.date).min().map{.init(id:id,start:$0)}}.sorted{$0.start<$1.start}
        deletions=records.compactMap(LapTimeDeletionEvent.normalize)
        // Only anonymous advancement counts are treated as format metadata. Never import
        // future driver results into replay ranking. Advancement needs corroborating
        // participation and a contiguous result block, even if eliminated rows are absent.
        let results=records.filter{$0.kind=="session_result"}
        let roster=Set(records.filter{$0.kind=="drivers"}.compactMap(\.driver))
        if !roster.isEmpty {
            for (index,phase) in phases.dropLast().enumerated() {
                let advanced=results.filter {r in let values=r.fields["duration"]?.array ?? [];return values.indices.contains(phase.id) && values[phase.id].number != nil}
                let next=phases[index+1],end=phases.indices.contains(index+2) ? phases[index+2].start:Date.distantFuture
                let nextParticipants=Set(laps.filter{$0.start>=next.start && $0.start<end}.map(\.driver))
                let advancedIDs=Set(advanced.compactMap(\.driver))
                let participants=results.filter{$0.driver.map{nextParticipants.contains($0)} == true}
                let positions=participants.compactMap{$0.fields.i("position")}.sorted()
                // Participation includes entrants who did not set a valid next-phase time.
                // Every participant must have a result, and the group must occupy the
                // complete leading classification block. No fixed elimination count.
                let corroborated = !advancedIDs.isEmpty && advancedIDs.isSubset(of:nextParticipants) && nextParticipants.isSubset(of:roster) && participants.count==nextParticipants.count
                if corroborated,!positions.isEmpty,positions==Array(1...positions.count) {cuts[phase.id]=positions.count}
            }
        }
    }
    func phase(at cursor:Date)->Int? {phases.last{$0.start<=cursor}?.id}
    func valid(_ lap:QualifyingLap,at cursor:Date)->Bool {
        let decision=deletions.filter{$0.timestamp<=cursor && $0.driverID==lap.driver && $0.matches(lap.state)}.max{$0.timestamp<$1.timestamp}
        return decision?.reinstated ?? true
    }
    func snapshot(at cursor:Date,drivers:[Int:DriverState],pits:[PitState])->QualifyingSnapshot {
        let known=laps.filter{$0.start<=cursor}
        let eligible=known.filter{!$0.outLap && valid($0,at:cursor)}
        let completed=eligible.filter{$0.finish.map{$0<=cursor} ?? false}
        var result=QualifyingSnapshot(phase:phase(at:cursor))
        result.cut=result.phase.flatMap{cuts[$0]}
        for driver in drivers.keys {
            var row=QualifyingDriverTiming(driver:driver)
            let own=known.filter{$0.driver==driver}
            let recentFinish=own.last {lap in
                guard let end=lap.finish else{return false}
                return !lap.outLap && end<=cursor && cursor.timeIntervalSince(end)<3
            }
            let current=recentFinish ?? own.last
            row.current=current
            for lap in completed where lap.driver==driver {
                if let p=phase(at:lap.start),let duration=lap.duration {row.phaseBests[p]=min(row.phaseBests[p] ?? .infinity,duration)}
            }
            row.rankPhase=row.phaseBests.keys.max() ?? 0
            row.best=row.phaseBests[result.phase ?? 0]
            row.phase=current.flatMap{phase(at:$0.start)}
            if let lap=current {
                let finished=lap.finish.map{$0<=cursor} ?? false
                // An unknown-duration lap ends at the next factual start; never use its future
                // pit flag or final record to guess an in-lap before the car enters the lane.
                row.state=lap.outLap ? "Out Lap":finished ? "Completed Lap":"Timed Lap"
                row.elapsed=finished ? lap.duration:max(0,cursor.timeIntervalSince(lap.start))
                if !valid(lap,at:cursor) {row.state="Lap Deleted"}
                for i in 0..<3 {
                    guard let time=lap.completion(i),time<=cursor,let value=lap.sectors[i] else{continue}
                    row.sectors[i]=value
                    guard !lap.outLap,valid(lap,at:cursor) else{continue}
                    let candidates=eligible.filter{$0.completion(i).map{$0<=cursor} ?? false}
                    let all=candidates.compactMap{$0.sectors[i]}.min()
                    let personal=candidates.filter{$0.driver==driver}.compactMap{$0.sectors[i]}.min()
                    row.merits[i]=all==value ? .sessionBest:personal==value ? .personalBest:.neutral
                }
                let count=row.sectors.prefix(while:{$0 != nil}).count
                if count>0,!lap.outLap,valid(lap,at:cursor),let reference=completed.filter({$0.driver==driver && $0.start<lap.start && phase(at:$0.start)==row.phase}).min(by:{$0.duration!<$1.duration!}),reference.sectors.prefix(count).allSatisfy({$0 != nil}) {
                    row.delta=row.sectors.prefix(count).compactMap{$0}.reduce(0,+)-reference.sectors.prefix(count).compactMap{$0}.reduce(0,+)
                }
                // PUSH needs evidence of competitive pace at this cursor; a timed lap alone
                // is insufficient (cooldown and in-laps also have ordinary lap records).
                if row.state=="Timed Lap",let s1=row.sectors[0] {
                    let prior=completed.filter{$0.driver==driver}.compactMap{$0.sectors[0]}.min()
                    if let prior,s1<=prior {row.state="Push Lap"}
                }
            }
            if row.phase != result.phase {row.current=nil;row.elapsed=nil;row.sectors=[nil,nil,nil];row.merits=[.neutral,.neutral,.neutral];row.delta=nil;row.state="No Time"}
            if pits.contains(where:{$0.driver==driver && $0.contains(cursor)}) {row.state="PIT";row.elapsed=nil;row.current=nil;row.sectors=[nil,nil,nil];row.merits=[.neutral,.neutral,.neutral];row.delta=nil}
            result.drivers[driver]=row
        }
        if let active=result.phase {
            for previous in phases where previous.id<active {
                guard let cut=cuts[previous.id] else{continue}
                let ranking=result.drivers.values.filter{$0.phaseBests[previous.id] != nil}.sorted {a,b in
                    let x=a.phaseBests[previous.id]!,y=b.phaseBests[previous.id]!
                    return x==y ? a.driver<b.driver:x<y
                }
                for row in ranking.dropFirst(cut) {result.drivers[row.driver]?.eliminated=true}
            }
        }
        result.order=drivers.keys.sorted {a,b in
            let x=result.drivers[a]!,y=result.drivers[b]!
            let xp=x.best != nil ? result.phase ?? 0:x.rankPhase
            let yp=y.best != nil ? result.phase ?? 0:y.rankPhase
            if xp != yp {return xp>yp}
            let xb=x.best ?? x.phaseBests[x.rankPhase] ?? .infinity,yb=y.best ?? y.phaseBests[y.rankPhase] ?? .infinity
            return xb==yb ? a<b:xb<yb
        }
        return result
    }
}
struct QualifyingSnapshot {
    var phase:Int?;var cut:Int?;var drivers:[Int:QualifyingDriverTiming]=[:];var order:[Int]=[]
    var leader:Double? {drivers.values.compactMap(\.best).min()}
}
struct QualifyingSlots {
    var pins:[Int?]=[nil,nil,nil];var automatic:[Int]=[];var changedAt:Date = .distantPast
    mutating func update(_ snapshot:QualifyingSnapshot,at cursor:Date) {
        guard cursor<changedAt || cursor.timeIntervalSince(changedAt)>=8 || automatic.isEmpty else{return}
        let ranked=snapshot.order.sorted {a,b in
            let priority=["Push Lap":0,"Timed Lap":1,"Completed Lap":2,"Out Lap":3,"PIT":4,"No Time":5]
            let x=priority[snapshot.drivers[a]?.state ?? ""] ?? 5,y=priority[snapshot.drivers[b]?.state ?? ""] ?? 5
            if x != y {return x<y};return (snapshot.order.firstIndex(of:a) ?? 999)<(snapshot.order.firstIndex(of:b) ?? 999)
        }
        automatic=ranked;changedAt=cursor
    }
    var visible:[Int?] {
        var used=Set(pins.compactMap{$0})
        return pins.map {pin in
            if let pin{return pin}
            guard let id=automatic.first(where:{!used.contains($0)}) else{return nil}
            used.insert(id);return id
        }
    }
    mutating func pin(_ driver:Int?,slot:Int) {
        guard pins.indices.contains(slot) else{return}
        if let driver {for i in pins.indices where pins[i]==driver {pins[i]=nil}}
        pins[slot]=driver
    }
}
