import XCTest
@testable import RaceCard
final class LapDeletionTests:XCTestCase {
    let t=Date(timeIntervalSince1970:1000)
    func message(_ text:String,_ seconds:Double)->NormalizedRecord {.init(id:text,date:t.addingTimeInterval(seconds),kind:"race_control",driver:nil,fields:["message":.string(text),"lap_number":.number(4),"scope":.string("Driver")])}
    func lap(_ number:Int,_ seconds:Double,_ duration:Double)->NormalizedRecord {.init(id:"lap-\(number)",date:t.addingTimeInterval(seconds),kind:"laps",driver:44,fields:["lap_number":.number(Double(number)),"lap_duration":.number(duration)])}
    func testExplicitReasonsTurnAndMissingReason() throws {
        for (reason,code) in [("TRACK LIMITS AT TURN 4","trackLimits"),("LEAVING THE TRACK","leavingTrack"),("SHORTCUTTING AND GAINING AN ADVANTAGE","advantage"),("YELLOW FLAG","yellowFlag"),("OTHER EXPLICIT REASON","other")] {
            let e=try XCTUnwrap(LapTimeDeletionEvent.normalize(message("CAR 44 (HAM) TIME 1:26.415 DELETED - "+reason,10)))
            XCTAssertEqual(e.deletedLapTime ?? 0,86.415,accuracy:0.0001);XCTAssertEqual(e.reason,code);XCTAssertEqual(e.driverID,44)
            if code=="trackLimits" {XCTAssertEqual(e.turn,4);XCTAssertTrue(e.text("en",name:"Hamilton").contains("1:26.415 · Track limits · T4"));XCTAssertTrue(e.text("ja",name:"ハミルトン").contains("トラックリミット違反 · T4"))}
            XCTAssertNil(StewardEvent.normalize(message(e.rawMessage,10)))
        }
        let withoutTime=try XCTUnwrap(LapTimeDeletionEvent.normalize(message("CAR 55 (SAI) LAP DELETED - TRACK LIMITS AT TURN 5 LAP 1 15:04:11",10)))
        XCTAssertNil(withoutTime.deletedLapTime);XCTAssertEqual(withoutTime.lapNumber,1);XCTAssertEqual(withoutTime.turn,5)
        XCTAssertTrue(withoutTime.text("en",name:"Sainz").contains("Track limits · T5 · Lap 1"))
        XCTAssertTrue(withoutTime.text("ja",name:"サインツ").contains("トラックリミット違反 · T5 · 1周目"))
        let missing=try XCTUnwrap(LapTimeDeletionEvent.normalize(message("CAR 44 TIME 1:26.415 DELETED",10)))
        XCTAssertNil(missing.reason);XCTAssertTrue(missing.text("ja",name:"ハミルトン").contains("理由未提供"));XCTAssertTrue(missing.text("en",name:"Hamilton").contains("Reason not provided"))
    }
    @MainActor func testFastestDeletionReinstatementReplayAndDeduplication() throws {
        let roster=NormalizedRecord(id:"driver",date:t,kind:"drivers",driver:44,fields:["full_name":.string("Lewis Hamilton"),"name_acronym":.string("HAM")])
        let deletion=message("CAR 44 TIME 1:26.415 DELETED - TRACK LIMITS AT TURN 4 LAP 2",30)
        let rows=[roster,lap(1,10,90),lap(2,20,86.415),deletion,deletion,lap(3,40,85)]
        let store=RaceStateStore()
        for cursor in [25.0,35,25,45,35,45] {
            store.reset(MockF1Provider.session,mode:.replay);store.ingest(rows,through:t.addingTimeInterval(cursor));store.currentTime=t.addingTimeInterval(cursor)
            XCTAssertEqual(store.fastest?.lap.number,cursor<30 ? 2:cursor<40 ? 1:3)
            XCTAssertEqual(store.drivers[44]?.bestLap?.number,cursor<30 ? 2:cursor<40 ? 1:3)
            let deleted=store.events.filter{$0.deletion != nil};XCTAssertEqual(deleted.count,cursor<30 ? 0:1)
            XCTAssertFalse(store.drivers[44]!.investigation);XCTAssertNil(store.drivers[44]?.penalty)
            if cursor>=30 {XCTAssertEqual(deleted.first?.driverNumbers,[44]);XCTAssertTrue(deleted.first!.localizedText("en").contains("Track limits · T4"));XCTAssertTrue(deleted.first!.localizedText("ja").contains("ハミルトン"))}
        }
        store.ingest([message("CAR 44 TIME 1:26.415 REINSTATED - TRACK LIMITS AT TURN 4 LAP 2",60)])
        XCTAssertTrue(store.lapIsValid(store.lapHistory[44]![2]!,driver:44))
    }
    @MainActor func testDeletionNeverInventsAccumulatedOffencesOrStewardStatus() {
        let roster=NormalizedRecord(id:"driver",date:t,kind:"drivers",driver:44,fields:["full_name":.string("Lewis Hamilton")])
        for (later,badge) in [("WARNING FOR CAR 44 - TRACK LIMITS","WARN"),("CAR 44 UNDER INVESTIGATION - TRACK LIMITS","INV"),("5 SECOND TIME PENALTY FOR CAR 44 - TRACK LIMITS","+5s"),("CAR 44 BLACK AND WHITE FLAG - TRACK LIMITS","")] {
            let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.replay)
            store.ingest([roster,message("CAR 44 TIME 1:26.415 DELETED - TRACK LIMITS AT TURN 4",10)])
            XCTAssertNil(store.drivers[44]?.penalty);XCTAssertFalse(store.drivers[44]!.investigation)
            store.ingest([message(later,20)])
            XCTAssertEqual(store.events.count,2)
            let d=store.drivers[44]!
            XCTAssertEqual(StatusRail.resolve(driver:d,state:nil,drsEnabled:false,precision:3,isRace:true).pill ?? "",badge)
            XCTAssertFalse(store.events.map{$0.localizedText("en")}.joined().contains("third offence"))
        }
    }
    @MainActor func testFocusUsesSameNormalizedEvent() async throws {
        let path=NSTemporaryDirectory()+UUID().uuidString
        let model=AppModel(cachePath:path)
        defer{try? FileManager.default.removeItem(atPath:path)}
        model.store.reset(MockF1Provider.session,mode:.replay)
        model.store.ingest([.init(id:"driver",date:t,kind:"drivers",driver:44,fields:["full_name":.string("Lewis Hamilton"),"name_acronym":.string("HAM")]),message("CAR 44 TIME 1:26.415 DELETED - TRACK LIMITS AT TURN 4",20)])
        model.store.selected=44
        XCTAssertEqual(model.focusedEvents.first,model.store.events.first);XCTAssertEqual(model.focusedEvents.first?.deletion?.turn,4)
        model.store.selected=1;XCTAssertTrue(model.focusedEvents.isEmpty)
    }
}
