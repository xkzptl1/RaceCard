import XCTest
@testable import RaceCard

final class V25Tests:XCTestCase {
    @MainActor func testItalianPositionBeforeDriverProfileSurvivesReplay() throws {
        let s=RaceStateStore();s.reset(MockF1Provider.session,mode:.replay)
        let t=MockF1Provider.start
        let position=OpenF1Mapper.map("position",["driver_number":.number(10),"position":.number(1),"date":.string(Dates.iso(t.addingTimeInterval(-3196)))],session:MockF1Provider.session)
        let profile=OpenF1Mapper.map("drivers",["driver_number":.number(10),"name_acronym":.string("GAS"),"full_name":.string("Pierre GASLY")],session:MockF1Provider.session)
        let start=OpenF1Mapper.map("race_control",["message":.string("RACE START"),"date":.string(Dates.iso(t.addingTimeInterval(211)))],session:MockF1Provider.session)
        s.ingest([position]);XCTAssertTrue(s.drivers.isEmpty)
        s.ingest([profile,start]);s.ingest([])
        let gas=try XCTUnwrap(s.drivers[10]);XCTAssertEqual(gas.acronym,"GAS")
        XCTAssertEqual(s.displayPosition(gas),1);XCTAssertNil(gas.gap)
        XCTAssertEqual(s.leaderboard.first?.id,10)
    }
    @MainActor func testGaslyPitStartCarryForwardAndStaleOrder() throws {
        let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.mock)
        let records=PitStartFixture.records()
        store.ingest(records.filter{$0.date<=MockF1Provider.start.addingTimeInterval(12)})
        XCTAssertEqual(store.raceStart.phase,.gridForming);XCTAssertTrue(store.raceStart.suppressGaps)
        XCTAssertEqual(store.leaderboard.first?.acronym,"GAS")
        XCTAssertNil(store.displayPosition(try XCTUnwrap(store.drivers[14])))
        XCTAssertTrue(store.drivers[30]?.pitStart == true)
        store.ingest(records.filter{$0.date>MockF1Provider.start.addingTimeInterval(12) && $0.date<=MockF1Provider.start.addingTimeInterval(25)})
        XCTAssertEqual(store.drivers[10]?.position,1);XCTAssertNil(store.drivers[10]?.gap)
        XCTAssertTrue(store.waitingForPosition(try XCTUnwrap(store.drivers[14])))
        store.currentTime=MockF1Provider.start.addingTimeInterval(29);store.ingest([])
        XCTAssertEqual(store.leaderboard.first?.id,10)
        var old=try XCTUnwrap(records.first{$0.kind=="position" && $0.driver==10});old.date=MockF1Provider.start;old.order=999999;old.fields["position"] = .number(20)
        store.ingest([old]);XCTAssertEqual(store.drivers[10]?.position,1)
        store.ingest(records.filter{$0.kind=="position" && $0.driver==14})
        XCTAssertEqual(store.displayPosition(try XCTUnwrap(store.drivers[14])),21)
        XCTAssertNil(store.displayPosition(try XCTUnwrap(store.drivers[30])))
    }
    @MainActor func testReplayCursorRejectsFutureAndCarriesForward() {
        let s=RaceStateStore();s.reset(MockF1Provider.session,mode:.replay)
        let records=PitStartFixture.records()
        s.ingest(records,through:MockF1Provider.start.addingTimeInterval(25))
        XCTAssertEqual(s.drivers[10]?.position,1);XCTAssertNil(s.drivers[14]?.position)
        XCTAssertFalse(s.events.contains{$0.category=="SAFETY CAR"})
        s.ingest([],through:MockF1Provider.start.addingTimeInterval(29));XCTAssertEqual(s.drivers[10]?.position,1)
        s.ingest(records,through:MockF1Provider.start.addingTimeInterval(35));XCTAssertEqual(s.drivers[14]?.position,21);XCTAssertNil(s.drivers[30]?.position)
    }
    @MainActor func testExplicitTimingSectorSafetyIsIndependentOfStaticLayers() throws {
        let s=RaceStateStore();s.reset(MockF1Provider.session,mode:.mock)
        let r=OpenF1Mapper.map("race_control",["date":.string(Dates.iso(MockF1Provider.start)),"flag":.string("RED"),"sector":.number(2),"scope":.string("TimingSector")],session:MockF1Provider.session)
        s.ingest([r]);XCTAssertEqual(s.raceControl.timingSectorFlags[2],"RED");XCTAssertEqual(s.raceControl.phase,.green)
        let g=try XCTUnwrap(TrackMetadataRepository().load(eventKey:"italy")?.geometry)
        XCTAssertEqual(g.timingSectorAreas?.map(\.number),[1,2,3]);XCTAssertTrue(g.valid)
        var unrelated=r;unrelated.id="marshal";unrelated.date=MockF1Provider.start.addingTimeInterval(1);unrelated.fields["scope"] = .string("Track");unrelated.fields["sector"] = .number(8);unrelated.fields["flag"] = .string("YELLOW")
        s.ingest([unrelated]);XCTAssertNil(s.raceControl.timingSectorFlags[8])
    }
    func testActualItalianRestartMessagesDoNotInventLightsOut() {
        let t=MockF1Provider.start;var s=RaceStartPresentation()
        s.ingest(lightCount:0,confirmedStart:false,at:t);XCTAssertNil(s.startedAt)
        s.ingest(lightCount:nil,confirmedStart:true,at:t)
        s.ingest(message:"EXTRA FORMATION LAP",lightCount:nil,confirmedStart:false,at:t.addingTimeInterval(100))
        XCTAssertEqual(s.phase,.formationLap);XCTAssertNil(s.startedAt)
        s.ingest(message:"STANDING START",lightCount:nil,confirmedStart:false,at:t.addingTimeInterval(110))
        XCTAssertEqual(s.phase,.startLights);XCTAssertNil(s.illuminated);XCTAssertNil(s.startedAt)
        XCTAssertEqual(EventNormalizer.classification("RACE START"),"SESSION START")
        XCTAssertEqual(EventNormalizer.classification("EXTRA FORMATION LAP"),"FORMATION LAP")
        XCTAssertEqual(EventNormalizer.classification("STANDING START"),"START PROCEDURE")
    }
    @MainActor func testLayerPersistenceAndSeasonMetadata() throws {
        let name=UUID().uuidString;let defaults=try XCTUnwrap(UserDefaults(suiteName:name));defer{defaults.removePersistentDomain(forName:name)}
        let first=MapLayers(defaults:defaults);first.set(.cars,false);first.set(.drsActivation,false);first.set(.lowGrip,true)
        let second=MapLayers(defaults:defaults);XCTAssertFalse(second.contains(.cars));XCTAssertFalse(second.contains(.drsActivation));XCTAssertTrue(second.contains(.lowGrip));XCTAssertFalse(second.contains(.referenceMap))
        second.set(.cars,true);XCTAssertFalse(second.contains(.referenceMap))
        let legacy=try XCTUnwrap(LegacyCircuitDocument.load(session:9165));XCTAssertEqual(legacy.geometry.zoneAnnotations.filter{$0.kind=="drsDetection"}.count,3)
        for event in ["japan","monaco","italy"] {let data=try XCTUnwrap(TrackMetadataRepository().load(eventKey:event));XCTAssertFalse(data.geometry?.informationMarkers?.isEmpty ?? true);XCTAssertFalse(data.geometry?.zoneAnnotations.contains{$0.kind.hasPrefix("drs")} ?? true)}
    }
    func testFormationLightsRequireFacts() {
        let t=MockF1Provider.start;var start=RaceStartPresentation()
        start.ingest(message:"FORMATION LAP STARTED",lightCount:nil,confirmedStart:false,at:t);XCTAssertEqual(start.phase,.formationLap)
        start.ingest(message:"GRID FORMING",lightCount:nil,confirmedStart:false,at:t.addingTimeInterval(10));XCTAssertEqual(start.phase,.gridForming)
        start.ingest(message:"START LIGHTS",lightCount:nil,confirmedStart:false,at:t.addingTimeInterval(15));XCTAssertTrue(start.visible(at:t.addingTimeInterval(16)));XCTAssertNil(start.illuminated);XCTAssertNil(start.startedAt)
        start.ingest(lightCount:nil,confirmedStart:true,at:t.addingTimeInterval(20));XCTAssertEqual(start.phase,.lightsOut)
        start.advance(at:t.addingTimeInterval(25));XCTAssertEqual(start.phase,.race);XCTAssertFalse(start.suppressGaps)
    }
    @MainActor func testCursorDerivedAlertLifecycleAndSuspension() {
        let s=RaceStateStore();s.reset(MockF1Provider.session,mode:.replay)
        func record(_ text:String,_ t:Double)->NormalizedRecord {OpenF1Mapper.map("race_control",["message":.string(text),"date":.string(Dates.iso(MockF1Provider.start.addingTimeInterval(t)))],session:MockF1Provider.session)}
        s.isRebuilding=true
        s.ingest([record("SAFETY CAR DEPLOYED",2)])
        s.currentTime=MockF1Provider.start.addingTimeInterval(3)
        XCTAssertEqual(s.visibleNotice?.category,"SAFETY CAR")
        s.currentTime=MockF1Provider.start.addingTimeInterval(8)
        XCTAssertNil(s.visibleNotice);XCTAssertEqual(s.raceControl.phase,.safetyCar)
        s.currentTime=MockF1Provider.start.addingTimeInterval(3)
        XCTAssertEqual(s.visibleNotice?.category,"SAFETY CAR")
        s.ingest([record("RED FLAG - RACE SUSPENDED",10),record("TRACK CLEAR",15),record("SAFETY CAR LIGHTS ON",20)])
        s.currentTime=MockF1Provider.start.addingTimeInterval(21)
        XCTAssertNil(s.visibleNotice);XCTAssertEqual(s.raceControl.phase,.red)
        XCTAssertNil(s.suspensions.first?.end)
        s.ingest([record("SESSION STARTED",30)])
        XCTAssertEqual(s.raceControl.phase,.green)
        XCTAssertEqual(s.suspensions.first?.end,MockF1Provider.start.addingTimeInterval(30))
    }
    @MainActor func testVSCEndingTrackClearAndNoStaleEvent() {
        let s=RaceStateStore();s.reset(MockF1Provider.session,mode:.replay)
        func record(_ text:String,_ t:Double)->NormalizedRecord {OpenF1Mapper.map("race_control",["message":.string(text),"date":.string(Dates.iso(MockF1Provider.start.addingTimeInterval(t)))],session:MockF1Provider.session)}
        s.ingest([record("VSC DEPLOYED",1),record("VSC ENDING",20)])
        s.currentTime=MockF1Provider.start.addingTimeInterval(26)
        XCTAssertTrue(s.safetyEnding);XCTAssertNil(s.visibleNotice)
        s.ingest([record("TRACK CLEAR",30)])
        s.currentTime=MockF1Provider.start.addingTimeInterval(31)
        XCTAssertEqual(s.raceControl.phase,.green);XCTAssertEqual(s.visibleNotice?.category,"RESTART")
        s.currentTime=MockF1Provider.start.addingTimeInterval(36);XCTAssertNil(s.visibleNotice)
    }
    @MainActor func testStaleStintAndPenaltyDoNotOverwriteNewerState() {
        let s=RaceStateStore();s.reset(MockF1Provider.session,mode:.mock);s.ingest(MockF1Provider.records().filter{$0.date==MockF1Provider.start})
        func r(_ kind:String,_ t:Double,_ fields:[String:JSONValue])->NormalizedRecord {var f=fields;f["driver_number"] = .number(4);f["date"] = .string(Dates.iso(MockF1Provider.start.addingTimeInterval(t)));return OpenF1Mapper.map(kind,f,session:MockF1Provider.session)}
        s.ingest([r("stints",20,["stint_number":.number(1),"lap_start":.number(1),"compound":.string("HARD")])]);s.ingest([r("stints",10,["stint_number":.number(1),"lap_start":.number(1),"compound":.string("SOFT")])]);XCTAssertEqual(s.drivers[4]?.currentStint?.compound,"HARD")
        s.ingest([r("race_control",30,["message":.string("CAR 4 - 10 SECOND TIME PENALTY")])]);s.ingest([r("race_control",10,["message":.string("CAR 4 - 5 SECOND TIME PENALTY")])]);XCTAssertEqual(s.drivers[4]?.penalty,"+10s")
    }
}
