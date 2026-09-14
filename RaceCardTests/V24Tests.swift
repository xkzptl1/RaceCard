import XCTest
@testable import RaceCard

final class V24Tests:XCTestCase {
    @MainActor func testFocusTimeoutHoverAndDirectSwitch() throws {
        let model=AppModel(cachePath:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        model.loadMock();model.focusDriver(4);let first=try XCTUnwrap(model.focusDeadline)
        model.advanceFocus(at:first.addingTimeInterval(-0.001));XCTAssertEqual(model.store.selected,4)
        model.focusHovered=true;model.advanceFocus(at:first);XCTAssertEqual(model.store.selected,4)
        XCTAssertEqual(model.focusDeadline,first.addingTimeInterval(10))
        model.focusHovered=false;model.advanceFocus(at:first.addingTimeInterval(9));XCTAssertEqual(model.store.selected,4)
        model.focusDriver(1);XCTAssertEqual(model.store.selected,1)
        model.advanceFocus(at:try XCTUnwrap(model.focusDeadline));XCTAssertNil(model.store.selected)
        model.focusDriver(16);model.dismissFocus();XCTAssertNil(model.store.selected);XCTAssertNil(model.focusDeadline)
    }
    @MainActor func testFocusedFeedUsesExplicitAssociationOnly() {
        let model=AppModel(cachePath:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        model.loadMock();let records=MockF1Provider.records();model.store.ingest(records.filter{$0.date>MockF1Provider.start && $0.date<=MockF1Provider.start.addingTimeInterval(200)})
        model.focusDriver(4);XCTAssertTrue(model.focusedEvents.contains{$0.category=="PIT"})
        XCTAssertFalse(model.focusedEvents.contains{["SAFETY CAR","VSC","YELLOW FLAG","PENALTY"].contains($0.category)})
        model.focusDriver(1);XCTAssertTrue(model.focusedEvents.contains{$0.category=="PENALTY"});XCTAssertFalse(model.focusedEvents.contains{$0.category=="PIT"})
        let r=OpenF1Mapper.map("race_control",["message":.string("CARS 4 (NOR) AND 1 (VER) NOTED - CAUSING A COLLISION"),"date":.string(Dates.iso(MockF1Provider.start.addingTimeInterval(201)))],session:MockF1Provider.session)
        model.store.ingest([r]);XCTAssertEqual(model.store.events.first?.driverNumbers,[1,4])
    }
    func testMultipleExplicitDriversAndNoLapNumberAssociation() {
        XCTAssertEqual(JapaneseRaceText.driverIDs("CARS 4, 16 AND 1 UNDER INVESTIGATION AT TURN 5"),[4,16,1])
        XCTAssertEqual(JapaneseRaceText.driverIDs("YELLOW IN SECTOR 2 LAP 15"),[])
        XCTAssertEqual(JapaneseRaceText.driverIDs("CAR 4 (NOR) - 5 SECOND TIME PENALTY"),[4])
    }
    func testTyreUsageSeparatesUnknownNewAndUsedSets() {
        var d=DriverState(id:4,name:"Lando Norris",acronym:"NOR",team:"McLaren",color:"FF8000")
        d.currentLap=10;d.stints=[StintState(id:2,compound:"HARD",start:8,end:nil,initialAge:nil)]
        XCTAssertEqual(d.stintLaps,3);XCTAssertNil(d.tyreAge)
        d.stints[0].initialAge=0;XCTAssertEqual(d.tyreAge,3)
        d.stints[0].initialAge=4;XCTAssertEqual(d.tyreAge,7)
    }
    @MainActor func testLeaderSortIgnoresGapAndInputOrder() {
        let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.mock)
        store.ingest(MockF1Provider.records().filter{$0.date==MockF1Provider.start})
        store.drivers[4]?.position=1;store.drivers[4]?.gap=nil
        store.drivers[1]?.position=2;store.drivers[1]?.gap="-1.234"
        XCTAssertEqual(store.leaderboard.first?.id,4)
        for gap in ["—","LEADER","首位","+2 LAP"] {store.drivers[4]?.gap=gap;XCTAssertEqual(store.leaderboard.first?.id,4)}
        let p=OpenF1Mapper.map("position",["driver_number":.number(1),"position":.number(1),"date":.string(Dates.iso(MockF1Provider.start.addingTimeInterval(10)))],session:MockF1Provider.session)
        store.ingest([p]);var old=p;old.date=MockF1Provider.start;old.fields["position"] = .number(22);store.ingest([old]);XCTAssertEqual(store.drivers[1]?.position,1)
    }
    func testStartLightsNeverAdvanceWithoutSourceEvidence() {
        let now=MockF1Provider.start;var start=RaceStartPresentation()
        XCTAssertFalse(start.visible(at:now));XCTAssertNil(start.illuminated)
        start.ingest(lightCount:2,confirmedStart:false,at:now)
        XCTAssertTrue(start.visible(at:now.addingTimeInterval(4)));XCTAssertEqual(start.illuminated,2)
        start.ingest(lightCount:5,confirmedStart:false,at:now.addingTimeInterval(1));XCTAssertEqual(start.illuminated,5)
        start.ingest(lightCount:3,confirmedStart:false,at:now.addingTimeInterval(-1));XCTAssertEqual(start.illuminated,5)
        start.ingest(lightCount:0,confirmedStart:false,at:now.addingTimeInterval(2));XCTAssertTrue(start.visible(at:now.addingTimeInterval(6)));XCTAssertFalse(start.visible(at:now.addingTimeInterval(7)))
        var fallback=RaceStartPresentation();fallback.ingest(lightCount:nil,confirmedStart:true,at:now)
        XCTAssertNil(fallback.illuminated);XCTAssertTrue(fallback.visible(at:now));XCTAssertFalse(fallback.visible(at:now.addingTimeInterval(5)))
        var invalid=RaceStartPresentation();invalid.ingest(lightCount:6,confirmedStart:false,at:now);XCTAssertFalse(invalid.visible(at:now))
        XCTAssertEqual(EventNormalizer.classification("SESSION START",flag:"GREEN"),"SESSION START")
    }
    func testWholeCalendarTypedLoadAndOfficialGeometry() throws {
        let repo=TrackMetadataRepository();let calendar=try XCTUnwrap(repo.calendar)
        XCTAssertEqual(calendar.events.count,23);XCTAssertEqual(Set(calendar.events.map(\.meetingKey)).count,23)
        for event in calendar.events {
            let d=try XCTUnwrap(repo.load(eventKey:event.eventKey),event.eventKey)
            XCTAssertEqual(d.circuit.identity.value.meetingKey,event.meetingKey);XCTAssertNotNil(d.zones);XCTAssertNotNil(d.tyres);XCTAssertNotNil(d.pit);XCTAssertNotNil(d.energy)
            XCTAssertNotNil(d.geometry,event.eventKey);XCTAssertFalse(d.provenance.sources.isEmpty)
        }
        XCTAssertEqual(repo.load(eventKey:"bahrain")?.circuit.identity.value.circuitName,"Kuala Lumpur")
        XCTAssertNil(repo.load(eventKey:"saudi-arabia"));XCTAssertNil(repo.load(season:2025,eventKey:"japan"));XCTAssertNil(repo.load(eventKey:"../japan"))
        XCTAssertEqual(repo.load(eventKey:"japan")?.geometry?.turns.count,18)
        XCTAssertEqual(repo.load(eventKey:"monaco")?.zones?.straightLineMode?.value.enabled,false)
        XCTAssertEqual(repo.load(eventKey:"italy")?.zones?.straightLineMode?.value.normalGripActivations.count,4)
    }
    func testPressureRevisionsAndSecondarySourceSeparation() throws {
        let repo=TrackMetadataRepository();let japan=try XCTUnwrap(repo.load(eventKey:"japan"))
        XCTAssertEqual(japan.tyres?.minimumPressures?.value.rearPsi,25)
        XCTAssertEqual(japan.tyres?.revisions.map(\.value.rearPsi),[25,26])
        XCTAssertEqual(japan.pit?.referencePitLossSeconds?.confidence,"secondary_source")
        XCTAssertEqual(japan.tyres?.dryCompounds?.confidence,"official_verified")
        let barcelona=try XCTUnwrap(repo.load(eventKey:"barcelona-catalunya"))
        XCTAssertEqual(barcelona.tyres?.revisions.map(\.value.frontPsi),[26,25])
        XCTAssertEqual(repo.load(eventKey:"bahrain")?.tyres?.dryCompounds?.value,["C2","C3","C4"])
        XCTAssertNil(repo.load(eventKey:"qatar")?.tyres?.minimumPressures)
    }
    func testMissingRepositoryFailsGracefully() {
        let repo=TrackMetadataRepository(root:URL(fileURLWithPath:"/nonexistent/racecard-test"));XCTAssertNil(repo.calendar);XCTAssertNil(repo.load(eventKey:"japan"))
    }
    func testOptionalOperationalMarkersRejectUnverifiedCoordinates() throws {
        let original=try XCTUnwrap(TrackMetadataRepository().root)
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder=temp.appendingPathComponent("2026/japan")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:temp)}
        try FileManager.default.copyItem(at:original.appendingPathComponent("calendar.json"),to:temp.appendingPathComponent("calendar.json"))
        try FileManager.default.copyItem(at:original.appendingPathComponent("2026/japan/sources.json"),to:folder.appendingPathComponent("sources.json"))
        var doc=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:original.appendingPathComponent("2026/japan/circuit.json"))) as? [String:Any])
        // Deliberate test-only coordinates, never part of the production library.
        doc["startFinish"]=["value":["x":0.5,"y":0.5],"sourceIds":["fia_map"],"confidence":"official_verified"]
        doc["pitEntry"]=["value":["x":2.0,"y":0.5],"sourceIds":["fia_map"],"confidence":"official_verified"]
        doc["pitExit"]=["value":["x":0.5,"y":0.5],"sourceIds":["somersf1"],"confidence":"secondary_source"]
        try JSONSerialization.data(withJSONObject:doc).write(to:folder.appendingPathComponent("circuit.json"))
        let loaded=try XCTUnwrap(TrackMetadataRepository(root:temp).load(eventKey:"japan"))
        XCTAssertEqual(loaded.operationalMarkers.map(\.label),["S/F"])
        XCTAssertNil(loaded.tyres)
    }

}
