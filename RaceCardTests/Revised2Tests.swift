import XCTest
import AppKit
@testable import RaceCard

final class Revised2Tests:XCTestCase {
    let session=MockF1Provider.session
    func record(_ kind:String,_ time:Double,_ fields:[String:JSONValue])->NormalizedRecord {
        OpenF1Mapper.map(kind,fields.merging(["driver_number":.number(14),"date":.string(Dates.iso(session.start.addingTimeInterval(time)))]){a,_ in a},session:session)
    }
    func stint(_ number:Int,_ lap:Int,_ compound:String,_ age:Int,_ time:Double)->NormalizedRecord {
        record("stints",time,["stint_number":.number(Double(number)),"lap_start":.number(Double(lap)),"compound":.string(compound),"tyre_age_at_start":.number(Double(age))])
    }
    @MainActor func state()->RaceStateStore {
        let s=RaceStateStore();s.reset(session,mode:.replay)
        s.ingest([record("drivers",0,["full_name":.string("Fernando Alonso"),"name_acronym":.string("ALO")])]);return s
    }
    @MainActor func testNormalCompoundChangesAndUsedSetGaugeAgreement() throws {
        let s=state();s.ingest([stint(1,1,"SOFT",0,0),stint(2,10,"MEDIUM",4,100),stint(3,20,"HARD",0,200)])
        XCTAssertEqual(s.tyreChanges.map{$0.fromCompound+">"+$0.toCompound},["SOFT>MEDIUM","MEDIUM>HARD"])
        XCTAssertEqual(s.drivers[14]?.currentStint?.compound,"HARD")
        XCTAssertEqual(s.drivers[14]?.stintLaps,1);XCTAssertEqual(s.drivers[14]?.tyreAge,1)
        XCTAssertEqual(s.tyreChanges.first?.priorUsage,4)
        let used=state();used.ingest([stint(1,1,"SOFT",0,0),stint(2,10,"MEDIUM",4,100)])
        used.drivers[14]?.currentLap=12
        XCTAssertEqual(used.drivers[14]?.stintLaps,3);XCTAssertEqual(used.drivers[14]?.tyreAge,7)
    }
    @MainActor func testSameCompoundNewStintResetsUsage() {
        let s=state();s.ingest([stint(1,1,"MEDIUM",4,0),stint(2,10,"MEDIUM",0,100)])
        XCTAssertEqual(s.tyreChanges.count,1);XCTAssertEqual(s.drivers[14]?.currentStint?.id,2)
        XCTAssertEqual(s.drivers[14]?.tyreAge,1)
    }
    @MainActor func testDuplicateStintsAndPitDescriptionsAreStable() {
        let s=state();let first=stint(1,1,"SOFT",0,0),second=stint(2,10,"MEDIUM",0,110)
        let pit=record("pit",100,["lap_number":.number(9),"stop_duration":.number(2.4)])
        s.ingest([first,pit,second,second,pit])
        var repeated=second;repeated.id="another-api-key";s.ingest([repeated])
        var duplicatePit=pit;duplicatePit.id="another-pit-key";s.ingest([duplicatePit])
        XCTAssertEqual(s.tyreChanges.count,1)
        XCTAssertEqual(s.events.filter{$0.category=="TYRE CHANGE"}.count,1)
        XCTAssertEqual(s.events.filter{$0.category=="PIT"}.count,1)
        XCTAssertNotNil(s.tyreChanges.first?.pitRecordID)
        XCTAssertEqual(s.tyreChanges.first?.pitStopDuration,2.4)
    }
    @MainActor func testStaleStintCannotReverseCurrentTyre() {
        let s=state();let a=stint(1,1,"MEDIUM",0,0),b=stint(2,10,"HARD",0,100)
        s.ingest([a,b]);s.ingest([a]);var stale=b;stale.id="stale";stale.date=session.start.addingTimeInterval(90);stale.fields["compound"] = .string("MEDIUM");s.ingest([stale])
        XCTAssertEqual(s.drivers[14]?.currentStint?.compound,"HARD")
        XCTAssertEqual(s.tyreChanges.map(\.toCompound),["HARD"])
    }
    @MainActor func testSeekBackwardForwardAndSpeedDoNotDuplicateHistory() {
        let rows=[record("drivers",0,["name_acronym":.string("ALO")]),stint(1,1,"SOFT",0,0),stint(2,10,"MEDIUM",0,100),stint(3,20,"HARD",2,200)]
        let s=state()
        func seek(_ t:Double) {s.isRebuilding=true;s.reset(session,mode:.replay);s.ingest(rows,through:session.start.addingTimeInterval(t));s.isRebuilding=false}
        seek(220);let ids=s.tyreChanges.map(\.id);seek(50);XCTAssertTrue(s.tyreChanges.isEmpty);seek(220);XCTAssertEqual(s.tyreChanges.map(\.id),ids)
        var clock=ReplayClock(start:session.start,end:session.end,time:session.start.addingTimeInterval(220))
        for speed in [1.0,2,5,10,50] {clock.speed=speed;s.ingest(rows,through:clock.time)}
        XCTAssertEqual(s.events.filter{$0.category=="TYRE CHANGE"}.count,2)
        XCTAssertTrue(s.notices.isEmpty)
    }
    @MainActor func testSelectedDriverFeedMatchesCurrentCompound() {
        let s=state();s.ingest([stint(1,1,"HARD",0,0),stint(2,10,"SOFT",4,100)]);s.selected=14
        let associated=s.events.filter{$0.driverNumbers.contains(14) && $0.category=="TYRE CHANGE"}
        XCTAssertEqual(associated.count,1);XCTAssertTrue(associated[0].text.contains("ハード → ソフト"))
        XCTAssertEqual(s.tyreChanges.last?.toCompound,s.drivers[14]?.currentStint?.compound)
    }
    @MainActor func testPitWithoutConfirmedBoundaryWithholdsTyreChange() {
        let s=state();s.ingest([stint(1,1,"MEDIUM",0,0),record("pit",100,["lap_number":.number(9)]),record("stints",110,["stint_number":.number(2),"compound":.string("HARD")])])
        XCTAssertEqual(s.events.filter{$0.category=="PIT"}.count,1);XCTAssertTrue(s.tyreChanges.isEmpty)
        XCTAssertFalse(s.tyreDiagnostics.isEmpty)
    }
    @MainActor func testStintWithoutPitTimingOmitsDurationAndUnknownCompoundIsWithheld() {
        let s=state();s.ingest([stint(1,1,"SOFT",0,0),stint(2,10,"HARD",3,100)])
        XCTAssertEqual(s.tyreChanges.count,1);XCTAssertNil(s.tyreChanges[0].pitStopDuration)
        s.ingest([stint(3,20,"UNKNOWN",0,200)]);XCTAssertEqual(s.tyreChanges.count,1);XCTAssertFalse(s.tyreDiagnostics.isEmpty)
    }
    func testHistoricalBoundaryCannotPrecedeMatchedPitEntry() {
        let s=stint(2,10,"HARD",0,50)
        let lap=record("laps",90,["lap_number":.number(10),"date_start":.string(Dates.iso(session.start.addingTimeInterval(90)))])
        let pit=record("pit",110,["lap_number":.number(9),"lane_duration":.number(20)])
        let normalized=OpenF1HistoricalProvider.normalizedStints([s],laps:[lap],pits:[pit],session:session)
        XCTAssertEqual(normalized[0].date,session.start.addingTimeInterval(130))
    }
    @MainActor func testHeadshotMemoryDiskCacheAndOfflineFallback() async throws {
        let notices=state()
        notices.ingest([record("drivers",0,["driver_number":.number(63),"name_acronym":.string("RUS")]),record("laps",1,["lap_number":.number(1),"lap_duration":.number(90)]),record("laps",2,["driver_number":.number(63),"lap_number":.number(1),"lap_duration":.number(89)])])
        XCTAssertEqual(notices.fastest?.driver,63)
        XCTAssertEqual(notices.notices.first?.driver,14,"A queued fastest-lap portrait belongs to that notice, not a later record holder")
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        actor Counter {var count=0;func increment(){count+=1}}
        let counter=Counter()
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        for x in 0..<2 {for y in 0..<2 {bitmap.setColor(.red,atX:x,y:y)}}
        let png=bitmap.representation(using:.png,properties:[:])!
        let repository=DriverImageRepository(root:folder,fetch:{_ in await counter.increment();return png})
        let first=await repository.imageData(url:"https://example.com/driver.png",season:2026)
        XCTAssertNotNil(first)
        let second=await repository.imageData(url:"https://example.com/driver.png",season:2026);XCTAssertEqual(first,second)
        let count=await counter.count;XCTAssertEqual(count,1)
        let offline=DriverImageRepository(root:folder,fetch:{_ in throw URLError(.notConnectedToInternet)})
        let cached=await offline.imageData(url:"https://example.com/driver.png",season:2026);XCTAssertEqual(cached,first)
        let missing=await offline.imageData(url:"https://example.com/missing.png",season:2026);XCTAssertNil(missing)
        _ = await repository.imageData(urls:["https://example.com/driver.png"],season:2026,identity:"verified-driver")
        let identityCached=await offline.cachedImageData(season:2027,identity:"verified-driver")
        XCTAssertEqual(identityCached,first,"Prior-season identity image is immediately available without a network request")
        let wrongIdentity=await offline.cachedImageData(season:2027,identity:"other-driver")
        XCTAssertNil(wrongIdentity)
    }
    func testRealHistoricalTyreCrossValidation() async throws {
        let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("RaceCard/history.sqlite")
        let cache=try HistoricalCache(path:folder.path),provider=OpenF1HistoricalProvider(cache:cache)
        let session=try await provider.prepare(provider.session(key:9165)){_ in}
        let store=await MainActor.run{let s=RaceStateStore();s.reset(session,mode:.replay);s.isRebuilding=true;return s}
        var offset=0
        while true {
            let rows=try await cache.read(session:9165,after:.distantPast,through:session.end,limit:5000,offset:offset)
            await MainActor.run {
                for r in rows where ["drivers","stints","pit","laps"].contains(r.kind) {
                    store.currentTime=r.date;store.ingest([r])
                    if r.kind=="stints",let id=r.driver,let latest=store.tyreChanges.filter({$0.driver==id}).last {
                        XCTAssertEqual(store.drivers[id]?.currentStint?.compound,latest.toCompound)
                    }
                }
            }
            if rows.count<5000 {break};offset+=rows.count
        }
        let report=await MainActor.run { ()->String in
            XCTAssertGreaterThan(store.tyreChanges.count,15)
            XCTAssertEqual(Set(store.tyreChanges.map(\.id)).count,store.tyreChanges.count)
            for change in store.tyreChanges {
                XCTAssertNotEqual(change.toCompound,"UNKNOWN")
                if let id=change.pitRecordID,let pit=store.drivers[change.driver]?.pits.first(where:{$0.id==id}) {XCTAssertGreaterThanOrEqual(change.date,pit.date)}
            }
            return store.tyreValidationReport()
        }
        try report.write(toFile:"/private/tmp/RaceCard-tyre-validation-9165.tsv",atomically:true,encoding:.utf8)
        let attachment=XCTAttachment(string:report);attachment.name="Real Singapore tyre cross-validation";attachment.lifetime = .keepAlways;add(attachment)
    }
    @MainActor func testHistoricalSeekContinuesWhenPositionEndpointIsRestricted() async throws {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[RestrictedPositionProtocol.self]
        let model=AppModel(cachePath:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,historicalTransport:URLSession(configuration:config))
        let rows=[record("drivers",0,["name_acronym":.string("ALO")]),stint(1,1,"SOFT",0,0),stint(2,10,"HARD",2,100)]
        try await model.cache.write(rows,session:session.id)
        model.store.reset(session,mode:.replay)
        model.clock = .init(start:session.start,end:session.end,time:session.start,speed:1,playing:false)
        let target=session.start.addingTimeInterval(110)
        model.seek(target,resumePlaying:false)
        for _ in 0..<30 {if model.clock.time==target {break};try await Task.sleep(for:.milliseconds(100))}
        XCTAssertEqual(model.clock.time,target);XCTAssertFalse(model.clock.playing)
        XCTAssertEqual(model.store.drivers[14]?.currentStint?.compound,"HARD")
        XCTAssertEqual(model.store.tyreChanges.count,1);XCTAssertTrue(model.store.positionDataUnavailable)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.store.positionDataMessage,"Historical positions temporarily restricted by provider · retrying automatically")
        let first=Int(floor(session.start.timeIntervalSince1970/120)),last=Int(floor(target.timeIntervalSince1970/120))
        for chunk in first...last {try await model.cache.mark("location:0:\(chunk)",session:session.id)}
        let cached=try await model.historical.locationsIfAvailable(session,from:session.start,through:target)
        XCTAssertTrue(cached,"Already cached ranges remain usable during the retry cooldown")
        await model.recoverHistoricalPositions()
        XCTAssertFalse(model.store.positionDataUnavailable,"Paused replay recovers when its location range becomes cached")
        XCTAssertNil(model.store.positionDataMessage)
        try await model.cache.write([record("laps",1,["lap_number":.number(1)]),record("laps",2,["lap_number":.number(1),"date_start":.string(Dates.iso(session.start.addingTimeInterval(3)))])],session:session.id)
        await model.seekLap(1)
        for _ in 0..<30 {if model.clock.time==session.start.addingTimeInterval(3) {break};try await Task.sleep(for:.milliseconds(100))}
        XCTAssertEqual(model.clock.time,session.start.addingTimeInterval(3),"Lap selection skips earlier records without a start timestamp")
        XCTAssertFalse(model.store.positionDataUnavailable)
    }
}

final class RestrictedPositionProtocol:URLProtocol {
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:401,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data("{\"detail\":\"Global API access restricted during live session\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
