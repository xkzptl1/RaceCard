import XCTest
@testable import RaceCard
final class StewardTests:XCTestCase {
    let start=MockF1Provider.start
    func record(_ message:String,_ seconds:Double=0,lap:Int=25)->NormalizedRecord {.init(id:message+String(seconds),date:start.addingTimeInterval(seconds),kind:"race_control",driver:nil,fields:["message":.string(message),"lap_number":.number(Double(lap)),"category":.string("Other"),"scope":.string("Driver")])}
    func parse(_ message:String,_ seconds:Double=0,lap:Int=25)->StewardEvent {StewardEvent.normalize(record(message,seconds,lap:lap))!}
    func testExplicitAndMissingReasonBothLanguages() {
        let reason=parse("CAR 27 UNDER INVESTIGATION - CAUSING A COLLISION")
        XCTAssertEqual(reason.reason?.code,"collision");XCTAssertTrue(reason.text("en").contains("Alleged causing a collision"));XCTAssertTrue(reason.text("ja").contains("可能性"))
        let missing=parse("CAR 27 UNDER INVESTIGATION")
        XCTAssertNil(missing.reason);XCTAssertTrue(missing.text("en").contains("Reason not provided"));XCTAssertTrue(missing.text("ja").contains("理由未提供"))
    }
    func testFiveTenDriveThroughStopGoAndNoFurtherAction() {
        let inv=parse("CAR 27 UNDER INVESTIGATION - CAUSING A COLLISION")
        for (text,badge) in [("5 SECOND TIME PENALTY FOR CAR 27 - CAUSING A COLLISION","+5s"),("10 SECOND TIME PENALTY FOR CAR 27 - CAUSING A COLLISION","+10s"),("DRIVE THROUGH PENALTY FOR CAR 27 - CAUSING A COLLISION","DT"),("STOP AND GO PENALTY FOR CAR 27 - CAUSING A COLLISION","SG"),("CAR 27 NO FURTHER ACTION - CAUSING A COLLISION","")] {
            let decision=parse(text,60),events=[inv,decision]
            for (offset,expected) in [(0.0,"INV"),(60,badge),(0,"INV"),(60,badge)] {
                let active=StewardTimeline.active(events,driver:27,at:start.addingTimeInterval(offset))
                XCTAssertEqual(active.first?.compact ?? "",expected)
                if offset>=60 {XCTAssertFalse(active.contains{$0.state == .investigation})}
            }
        }
    }
    func testWarningReprimandGridAndDisqualificationAreExplicit() {
        XCTAssertEqual(parse("WARNING FOR CAR 27").penalty,.warning)
        XCTAssertEqual(parse("REPRIMAND FOR CAR 27").penalty,.reprimand)
        XCTAssertEqual(parse("CAR 27 DISQUALIFIED").penalty,.disqualified)
        XCTAssertEqual(parse("3 PLACE GRID PENALTY FOR CAR 27").penalty,.grid(3))
        XCTAssertNil(parse("PENALTY FOR CAR 27").penalty)
        XCTAssertNil(StewardEvent.normalize(record("CAR 27 PASSED TURN 4")))
    }
    func testIndependentInvestigationsAndConservativeCorrelation() {
        let collision=parse("CAR 27 UNDER INVESTIGATION - CAUSING A COLLISION",0)
        let limits=parse("CAR 27 UNDER INVESTIGATION - TRACK LIMITS",10)
        let decision=parse("5 SECOND TIME PENALTY FOR CAR 27 - TRACK LIMITS",60)
        let items=StewardTimeline.active([collision,limits,decision],driver:27,at:start.addingTimeInterval(100))
        XCTAssertEqual(items.count,2);XCTAssertEqual(items.first?.compact,"+5s");XCTAssertEqual(items.last?.reason?.code,"collision")
        let unknown=parse("CAR 27 NO FURTHER ACTION",30)
        XCTAssertEqual(StewardTimeline.active([collision,limits,unknown],driver:27,at:start.addingTimeInterval(40)).count,2)
        let otherTime=parse("CAR 27 UNDER INVESTIGATION - CAUSING A COLLISION (14:20:20)",20)
        let earlierTime=parse("CAR 27 UNDER INVESTIGATION - CAUSING A COLLISION (14:10:10)",10)
        XCTAssertEqual(StewardTimeline.active([otherTime,earlierTime],driver:27,at:start.addingTimeInterval(40)).count,2)
    }
    @MainActor func testEventSourcedFeedStatusReplayAndUnrelatedDNF() throws {
        let driver=NormalizedRecord(id:"driver",date:start,kind:"drivers",driver:27,fields:["full_name":.string("Nico Hülkenberg"),"name_acronym":.string("HUL")])
        let inv=record("CAR 27 UNDER INVESTIGATION - CAUSING A COLLISION",10)
        let penalty=record("5 SECOND TIME PENALTY FOR CAR 27 - CAUSING A COLLISION",60)
        for cursor in [10.0,60,10,60] {
            let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.replay);store.currentTime=start.addingTimeInterval(cursor)
            store.ingest([driver,penalty,inv,penalty],through:store.currentTime)
            let d=try XCTUnwrap(store.drivers[27]);XCTAssertEqual(d.investigation,cursor<60)
            XCTAssertEqual(store.events.count,cursor<60 ? 1:2)
            XCTAssertTrue(store.events.allSatisfy{$0.steward != nil})
            XCTAssertEqual(StatusRail.resolve(driver:d,state:nil,drsEnabled:false,precision:3,isRace:true).pill,cursor<60 ? "INV":"+5s")
            XCTAssertEqual(StatusRail.resolve(driver:d,state:"DNF",drsEnabled:false,precision:3,isRace:true).pill,"DNF")
            XCTAssertTrue(store.events.first!.localizedText("en").contains("Hülkenberg"));XCTAssertTrue(store.events.first!.localizedText("ja").contains("ヒュルケンベルグ"))
        }
    }
    func testActualMonzaPerezAndRussellMessages() {
        let p1=parse("FIA STEWARDS: INCIDENT INVOLVING CAR 11 (PER) WILL BE INVESTIGATED AFTER THE RACE - FAILING TO FOLLOW RACE DIRECTORS INSTRUCTIONS – PRACTICE START INFRINGEMENT (14:20:30)",0,lap:1)
        let p2=parse("FIA STEWARDS: TURN 1 INCIDENT INVOLVING CAR 11 (PER) UNDER INVESTIGATION - FAILING TO FOLLOW RACE DIRECTORS INSTRUCTIONS – ESCAPE ROAD INSTRUCTIONS (16:09:46)",6500,lap:28)
        let p3=parse("FIA STEWARDS: 5 SECOND TIME PENALTY FOR CAR 11 (PER) - FAILING TO FOLLOW RACE DIRECTORS INSTRUCTIONS – ESCAPE ROAD INSTRUCTIONS",6782,lap:30)
        let active=StewardTimeline.active([p1,p2,p3],driver:11,at:start.addingTimeInterval(7000))
        XCTAssertEqual(active.count,2);XCTAssertEqual(active.first?.compact,"+5s");XCTAssertEqual(active.last?.reason?.code,"practiceStart")
        let r1=parse("FIA STEWARDS: INCIDENT INVOLVING CAR 63 (RUS) UNDER INVESTIGATION - YELLOW FLAG INFRINGEMENT (16:17:30)",0,lap:37)
        let r2=parse("FIA STEWARDS: INCIDENT INVOLVING CAR 63 (RUS) NO FURTHER ACTION - YELLOW FLAG INFRINGEMENT (16:17:30)",249,lap:40)
        XCTAssertTrue(StewardTimeline.active([r1,r2],driver:63,at:start.addingTimeInterval(250)).isEmpty)
    }
    @MainActor func testDistinctSimultaneousFeedEventsAndInvestigationPriorityOverWarning() throws {
        let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.replay);store.currentTime=start.addingTimeInterval(100)
        store.ingest([.init(id:"d",date:start,kind:"drivers",driver:27,fields:["full_name":.string("Nico Hülkenberg")]),record("CAR 27 UNDER INVESTIGATION - TRACK LIMITS",10),record("CAR 27 UNDER INVESTIGATION - CAUSING A COLLISION",10),record("WARNING FOR CAR 27 - YELLOW FLAG INFRINGEMENT",20)])
        let d=try XCTUnwrap(store.drivers[27]);XCTAssertEqual(store.events.count,3);XCTAssertEqual(d.stewardItems.count,3)
        XCTAssertEqual(StatusRail.resolve(driver:d,state:nil,drsEnabled:false,precision:3,isRace:true).pill,"INV")
    }

    @MainActor func testDriverBootstrapRestoresEarlierInvestigationAndNames() throws {
        let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.replay)
        store.ingest([record("CAR 27 WILL BE INVESTIGATED AFTER THE RACE - TRACK LIMITS",1)])
        store.ingest([.init(id:"late-driver",date:start.addingTimeInterval(10),kind:"drivers",driver:27,fields:["full_name":.string("Nico Hülkenberg"),"name_acronym":.string("HUL")])])
        XCTAssertTrue(try XCTUnwrap(store.drivers[27]).investigation)
        XCTAssertTrue(store.events[0].localizedText("en").contains("Hülkenberg"))
        XCTAssertTrue(store.events[0].localizedText("en").contains("after the race"))
        XCTAssertTrue(store.events[0].localizedText("ja").contains("レース後"))
    }

    @MainActor func testOfficialResultDoesNotInventStewardClearance() throws {
        let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.replay)
        store.ingest([.init(id:"d",date:start,kind:"drivers",driver:27,fields:["full_name":.string("Nico Hülkenberg")]),record("CAR 27 UNDER INVESTIGATION",10),.init(id:"result",date:start.addingTimeInterval(100),kind:"session_result",driver:27,fields:["dnf":.bool(true)])])
        let d=try XCTUnwrap(store.drivers[27]);XCTAssertTrue(d.investigation);XCTAssertEqual(d.status,"DNF")
        XCTAssertEqual(StatusRail.resolve(driver:d,state:d.status,drsEnabled:false,precision:3,isRace:true).pill,"DNF")
    }

}
