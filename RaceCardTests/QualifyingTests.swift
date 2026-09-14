import XCTest
@testable import RaceCard

final class QualifyingTests:XCTestCase {
    func fixture(_ key:Int)throws->(SessionState,[NormalizedRecord],[Int:DriverState]) {
        let root=URL(fileURLWithPath:"/private/tmp/RaceCardQualifyingRaw")
        func rows(_ kind:String)throws->[[String:JSONValue]] {try OpenF1Mapper.rows(Data(contentsOf:root.appendingPathComponent("\(key)-\(kind).json")))}
        let session=try XCTUnwrap(OpenF1Mapper.session(rows("sessions")[0]))
        let records=try ["drivers","laps","race_control","session_result","pit","stints"].flatMap {kind in try rows(kind).map{OpenF1Mapper.map(kind,$0,session:session)}}
        let drivers=try Dictionary(uniqueKeysWithValues:rows("drivers").map{f in let id=f.i("driver_number")!;return(id,DriverState(id:id,name:f.s("full_name")!,acronym:f.s("name_acronym")!,team:f.s("team_name") ?? "",color:f.s("team_colour") ?? "888888"))})
        return(session,records,drivers)
    }
    func testRealThreeCircuitSectorBoundariesAndRewinds()throws {
        for key in [11365,11249,11349] {
            let (_,records,drivers)=try fixture(key),timeline=QualifyingTimeline(records:records)
            XCTAssertEqual(timeline.phases.map(\.id),[1,2,3])
            for phase in timeline.phases {
                XCTAssertEqual(timeline.phase(at:phase.start),phase.id)
                let selected=timeline.laps.filter{!$0.outLap && $0.duration != nil && $0.sectors.allSatisfy{$0 != nil} && timeline.phase(at:$0.start)==phase.id}
                for driver in Array(Set(selected.map(\.driver))).sorted().prefix(3) {
                    let lap=selected.first{$0.driver==driver}!
                    for i in 0..<3 {
                        let boundary=try XCTUnwrap(lap.completion(i))
                        let before=timeline.snapshot(at:boundary.addingTimeInterval(-0.002),drivers:drivers,pits:[])
                        XCTAssertNil(before.drivers[driver]?.sectors[i],"\(key) \(driver) S\(i+1)")
                        let after=timeline.snapshot(at:boundary,drivers:drivers,pits:[])
                        XCTAssertEqual(after.drivers[driver]?.sectors[i],lap.sectors[i])
                        let again=timeline.snapshot(at:boundary.addingTimeInterval(-0.002),drivers:drivers,pits:[])
                        XCTAssertNil(again.drivers[driver]?.sectors[i])
                    }
                }
            }
        }
    }
    func testRealDeletionsRemoveSectorEligibilityAtSourceTimestamp()throws {
        for key in [11365,11249,11349] {
            let (_,records,drivers)=try fixture(key),timeline=QualifyingTimeline(records:records)
            let deletion=try XCTUnwrap(timeline.deletions.first{event in timeline.laps.contains{event.driverID==$0.driver && event.matches($0.state)}})
            let lap=try XCTUnwrap(timeline.laps.first{deletion.driverID==$0.driver && deletion.matches($0.state)})
            XCTAssertTrue(timeline.valid(lap,at:deletion.timestamp.addingTimeInterval(-0.001)))
            XCTAssertFalse(timeline.valid(lap,at:deletion.timestamp))
            let forward=timeline.snapshot(at:deletion.timestamp,drivers:drivers,pits:[])
            _=timeline.snapshot(at:deletion.timestamp.addingTimeInterval(-10),drivers:drivers,pits:[])
            XCTAssertEqual(forward.order,timeline.snapshot(at:deletion.timestamp,drivers:drivers,pits:[]).order)
        }
    }
    func testRealPhaseBestsMatchFinalSource()throws {
        for key in [11365,11249,11349] {
            let (session,records,drivers)=try fixture(key),timeline=QualifyingTimeline(records:records)
            let snapshot=timeline.snapshot(at:session.end.addingTimeInterval(1800),drivers:drivers,pits:[])
            for r in records where r.kind=="session_result" {
                for (i,value) in (r.fields["duration"]?.array ?? []).enumerated() {
                    guard let expected=value.number,let driver=r.driver else{continue}
                    XCTAssertEqual(snapshot.drivers[driver]?.phaseBests[i+1] ?? -1,expected,accuracy:0.002,"session \(key) driver \(driver) Q\(i+1)")
                }
            }
        }
    }
    func testExportRealComparisonsAndCursorMerits()throws {
        var output:[[String:Any]]=[]
        for key in [11365,11249,11349] {
            let (session,records,drivers)=try fixture(key),timeline=QualifyingTimeline(records:records)
            XCTAssertEqual(timeline.cuts,[1:16,2:10])
            let resultDrivers=records.filter{$0.kind=="session_result"}.sorted{($0.fields.i("position") ?? 99)<($1.fields.i("position") ?? 99)}.prefix(3).compactMap(\.driver)
            for phase in timeline.phases {
                for driver in resultDrivers {
                    let lap=try XCTUnwrap(timeline.laps.filter{$0.driver==driver && !$0.outLap && timeline.phase(at:$0.start)==phase.id && $0.duration != nil && timeline.valid($0,at:session.end.addingTimeInterval(1800))}.min{$0.duration!<$1.duration!})
                    let cursor=lap.finish!.addingTimeInterval(0.2),snapshot=timeline.snapshot(at:cursor,drivers:drivers,pits:[])
                    let rendered=try XCTUnwrap(snapshot.drivers[driver])
                    XCTAssertEqual(rendered.current?.number,lap.number)
                    XCTAssertEqual(rendered.sectors,lap.sectors)
                    for i in 0..<3 {
                        let valid=timeline.laps.filter{!$0.outLap && timeline.valid($0,at:cursor) && $0.completion(i).map{$0<=cursor} == true}
                        let all=valid.compactMap{$0.sectors[i]}.min(),own=valid.filter{$0.driver==driver}.compactMap{$0.sectors[i]}.min()
                        XCTAssertEqual(rendered.merits[i],lap.sectors[i]==all ? .sessionBest:lap.sectors[i]==own ? .personalBest:.neutral)
                    }
                    output.append(["session":key,"driver":driver,"acronym":drivers[driver]!.acronym,"phase":phase.id,"lap":lap.number,"cursor":Dates.iso(cursor),"sourceSectors":lap.sectors.map{$0 ?? -1},"renderedSectors":rendered.sectors.map{$0 ?? -1},"sourceLap":lap.duration!,"renderedLap":rendered.elapsed ?? -1,"valid":timeline.valid(lap,at:cursor),"sectorMerits":rendered.merits.map(\.rawValue),"phaseBest":rendered.best ?? -1,"cut":snapshot.cut ?? 0])
                }
            }
        }
        try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"/private/tmp/RaceCardQualifyingRaw/rendered-comparisons.json"))
    }
    func testPinsDwellAndSessionMode() {
        XCTAssertTrue(SessionState(id:1,meeting:1,title:"",circuit:"",type:"Sprint Qualifying",start:Date(),end:Date()).isQualifying)
        var slots=QualifyingSlots();let t=Date();slots.update(.init(order:[1,2,3,4]),at:t)
        slots.update(.init(order:[4,3,2,1]),at:t.addingTimeInterval(2));XCTAssertEqual(slots.visible,[1,2,3])
        slots.pin(4,slot:0);XCTAssertEqual(slots.visible,[4,1,2]);slots.pin(3,slot:1);slots.pin(2,slot:2);XCTAssertEqual(slots.visible,[4,3,2])
        slots.pin(3,slot:0);XCTAssertEqual(slots.pins,[3,nil,2])
    }
    @MainActor func testRealQualifyingOutLapsNeverProduceFastestLapEvents() throws {
        for key in [11365,11249,11349] {
            let (session,records,_)=try fixture(key)
            let store=RaceStateStore();store.reset(session,mode:.historical)
            for record in records.filter({$0.kind == "drivers"}) {store.apply(record)}
            for record in records.filter({$0.kind == "laps" && $0.fields.b("is_pit_out_lap")}).sorted(by:{$0.date<$1.date}) {store.apply(record)}
            XCTAssertNil(store.fastest)
            XCTAssertFalse(store.events.contains{$0.category == "FASTEST LAP"})
        }
    }
    func testRealMapEmphasisUsesOnlyRecentCompletedValidSectors() throws {
        for key in [11365,11249,11349] {
            let (_,records,drivers)=try fixture(key),timeline=QualifyingTimeline(records:records)
            let lap=try XCTUnwrap(timeline.laps.first{!$0.outLap && $0.sectors.allSatisfy{$0 != nil} && $0.duration != nil})
            let boundary=try XCTUnwrap(lap.completion(0))
            let before=timeline.snapshot(at:boundary.addingTimeInterval(-0.001),drivers:drivers,pits:[])
            XCTAssertNil(QualifyingMapTiming.emphasis(before.drivers[lap.driver],at:boundary.addingTimeInterval(-0.001))[1])
            let after=timeline.snapshot(at:boundary,drivers:drivers,pits:[])
            XCTAssertEqual(QualifyingMapTiming.emphasis(after.drivers[lap.driver],at:boundary)[1],after.drivers[lap.driver]?.merits[0])
            XCTAssertNil(QualifyingMapTiming.emphasis(after.drivers[lap.driver],at:boundary.addingTimeInterval(8))[1])
            var deleted=after.drivers[lap.driver]!;deleted.state="Lap Deleted"
            XCTAssertTrue(QualifyingMapTiming.emphasis(deleted,at:boundary).isEmpty)
        }
    }
    func testSectorLaneGeometryPreservesRecordedPointsAndBoundaries() {
        let lap=(0..<16).map{TrackPoint(x:Double($0),y:Double($0%4))}
        let lanes=QualifyingMapTiming.strokes(lap:lap,boundaries:[1:lap[5],2:lap[10]])
        XCTAssertEqual(lanes.map(\.number),[1,2,3])
        XCTAssertEqual(lanes[0].points,Array(lap[0...5]))
        XCTAssertEqual(lanes[1].points,Array(lap[5...10]))
        XCTAssertEqual(lanes[2].points,Array(lap[10...])+[lap[0]])
        XCTAssertTrue(QualifyingMapTiming.strokes(lap:lap,boundaries:[1:lap[10],2:lap[5]]).isEmpty)
    }
    func testCorroboratedMadridCutAndRandomFixtures() throws {
        for key in [11365,11303,11330] {
            let (_,records,_)=try fixture(key)
            XCTAssertEqual(QualifyingTimeline(records:records).cuts,[1:16,2:10])
        }
        let (_,records,_)=try fixture(11365)
        // Removing the last advancing result could otherwise falsely suggest a smaller cut.
        let missing=records.filter{!($0.kind=="session_result" && $0.fields.i("position")==16)}
        XCTAssertNil(QualifyingTimeline(records:missing).cuts[1])
        let noCorroboration=records.filter{$0.kind != "laps"}
        XCTAssertTrue(QualifyingTimeline(records:noCorroboration).cuts.isEmpty)
    }
    func testQualifyingMovementExpiresAndClearsOnSeekAndPhaseChange() {
        var a=QualifyingSnapshot(phase:1,drivers:[1:.init(driver:1,best:90),2:.init(driver:2,best:91)],order:[1,2])
        var motion=QualifyingRankMotion();let now=Date()
        motion.update(a,at:now);XCTAssertEqual(motion.movement(1,at:now),0)
        a.order=[2,1];a.drivers[2]?.best=89
        motion.update(a,at:now);XCTAssertEqual(motion.movement(2,at:now),1);XCTAssertEqual(motion.movement(1,at:now),-1)
        motion.update(a,at:now.addingTimeInterval(2));XCTAssertEqual(motion.movement(2,at:now.addingTimeInterval(4)),0)
        a.order=[1,2];motion.update(a,at:now,reset:true);XCTAssertEqual(motion.movement(1,at:now),0)
        a.phase=2;a.order=[2,1];motion.update(a,at:now);XCTAssertEqual(motion.movement(2,at:now),0)
    }
}
