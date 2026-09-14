import XCTest
@testable import RaceCard

final class V26Tests:XCTestCase {
    @MainActor func testFuturePositionsDoNotAdvanceRaceState() {
        let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.replay)
        let time=MockF1Provider.start
        let record=NormalizedRecord(id:"future-location",order:0,date:time.addingTimeInterval(1),kind:"location",driver:4,fields:["x":.number(100),"y":.number(50)])
        store.recordPositionSamples([record])
        XCTAssertTrue(store.drivers.isEmpty);XCTAssertTrue(store.events.isEmpty)
        XCTAssertEqual(store.currentTime,MockF1Provider.session.start)
    }
    func testLapOneAnchorReconstructsLightsWithoutFormation() {
        let anchor=Date(timeIntervalSince1970:100)
        var start=RaceStartPresentation();start.factualAnchor=anchor
        XCTAssertEqual(start.lightState(at:anchor.addingTimeInterval(-2))?.illuminated,5)
        XCTAssertEqual(start.phase,.preGrid)
        start.advance(at:anchor)
        XCTAssertTrue(start.hasStarted);XCTAssertEqual(start.lightState(at:anchor)?.illuminated,0)
        XCTAssertNil(start.lightState(at:anchor.addingTimeInterval(10)))
        var rebuilt=RaceStartPresentation();rebuilt.factualAnchor=anchor
        XCTAssertEqual(rebuilt.lightState(at:anchor.addingTimeInterval(-2))?.illuminated,5)
    }
    @MainActor func testAllBundledSessionDriversHaveNationality() throws {
        let root=try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("IdentityMetadata"))
        let drivers=try DriverMetadataRepository(root:root).drivers
        let snapshots=try JSONDecoder().decode([DriverSnapshot].self,from:Data(contentsOf:root.appendingPathComponent("snapshots.json")))
        let registry=DriverRegistry(records:snapshots,metadata:drivers)
        XCTAssertGreaterThanOrEqual(snapshots.count,22)
        for record in snapshots {
            let resolved=registry.resolve(number:record.number,season:record.season,session:record.sessionKey,meeting:record.meetingKey,date:record.date)
            XCTAssertNotNil(Nationality.display(resolved.nationality,language:"en"),record.fullName)
            XCTAssertNotNil(Nationality.display(resolved.nationality,language:"ja"),record.fullName)
        }
    }
    @MainActor func testHistoricalMapDoesNotBorrowAnotherSeasonsOperationalZones() throws {
        let repository=TrackMetadataRepository()
        let reference=try XCTUnwrap(repository.load(eventKey:"australia"))
        XCTAssertFalse(try XCTUnwrap(reference.geometry).zoneAnnotations.isEmpty)
        let store=RaceStateStore()
        let date=try XCTUnwrap(Dates.parse("2025-03-16T04:00:00Z"))
        let session=SessionState(id:9693,meeting:1254,title:"Australia",circuit:"Melbourne",type:"Race",start:date,end:date.addingTimeInterval(7200))
        store.reset(session,mode:.historical)
        let scene=CanonicalMap(store:store,reference:reference,metadataRoot:repository.root,layers:MapLayers(),onBackgroundTap:{})
        XCTAssertTrue(try XCTUnwrap(scene.officialGeometry).zoneAnnotations.isEmpty)
        XCTAssertTrue(scene.officialMarkers.isEmpty)
        XCTAssertFalse(try XCTUnwrap(reference.geometry).zoneAnnotations.isEmpty)
    }

}
