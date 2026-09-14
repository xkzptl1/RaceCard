import XCTest
@testable import RaceCard

final class FinalPolishTests:XCTestCase {
    let start=Date(timeIntervalSince1970:1000)
    func record(_ kind:String,_ offset:Double,_ fields:[String:JSONValue],driver:Int?=4)->NormalizedRecord {.init(id:"\(kind)-\(offset)-\(driver ?? 0)",date:start.addingTimeInterval(offset),kind:kind,driver:driver,fields:fields)}
    @MainActor func testStructuredFeedRendersBothLanguagesWithoutReingestion() throws {
        let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.replay)
        store.ingest([record("drivers",0,["full_name":.string("Lando Norris"),"name_acronym":.string("NOR")]),record("pit",10,["lap_number":.number(3),"stop_duration":.number(2.4),"lane_duration":.number(22.8)]),record("race_control",12,["message":.string("RED FLAG"),"flag":.string("RED")],driver:nil)])
        let pit=try XCTUnwrap(store.events.first{$0.category=="PIT"})
        XCTAssertTrue(pit.localizedText("en").contains("Stop 2.400s"));XCTAssertTrue(pit.localizedDetail("en").contains("Pit-lane duration 0:22.800"))
        XCTAssertTrue(pit.localizedText("en").contains("During red-flag"));XCTAssertTrue(pit.localizedText("ja").contains("ノリス"))
        XCTAssertFalse(pit.localizedText("en").contains("ノリス"));XCTAssertEqual(pit.localizedText("en"),pit.localizedText("en"))
        let encoded=try JSONEncoder().encode(pit),decoded=try JSONDecoder().decode(FeedEvent.self,from:encoded)
        XCTAssertEqual(decoded.localizedText("ja"),pit.localizedText("ja"))
    }
    @MainActor func testPitEntryExitSecondStopSuspensionAndRepeatedSeeks() throws {
        let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.replay)
        store.ingest([record("drivers",0,["full_name":.string("Lando Norris")]),record("pit",10,["lane_duration":.number(20)]),record("pit",50,["lane_duration":.number(1800)])])
        let driver=try XCTUnwrap(store.drivers[4])
        for (offset,expected) in [(9,CurrentPitState.outside),(10,.normalPit),(29,.normalPit),(30,.outside),(50,.normalPit),(1850,.outside),(20,.normalPit),(40,.outside),(50,.normalPit)] {
            store.currentTime=start.addingTimeInterval(Double(offset));XCTAssertEqual(store.pitState(driver),expected)
        }
        store.ingest([record("race_control",60,["message":.string("RED FLAG"),"flag":.string("RED")],driver:nil)])
        store.currentTime=start.addingTimeInterval(70);XCTAssertEqual(store.pitState(driver),.pitDuringSuspension);XCTAssertNil(store.status(driver))
        store.ingest([record("race_control",1800,["message":.string("GREEN LIGHT - PIT EXIT OPEN"),"flag":.string("GREEN")],driver:nil)])
        XCTAssertTrue(driver.pits[1].intersects(store.suspensions))
        store.currentTime=start.addingTimeInterval(1850);XCTAssertEqual(store.pitState(driver),.outside)
    }
    func testTelemetryCursorDriverDiscreteStateAndStaleness() {
        let rows=[record("car_data",0,["speed":.number(101),"n_gear":.number(3),"rpm":.number(9000),"throttle":.number(80),"brake":.number(0),"drs":.number(12)]),record("car_data",10,["speed":.number(220),"n_gear":.number(6),"rpm":.number(12000),"throttle":.number(100),"brake":.number(100),"drs":.number(0)]),record("car_data",10,["speed":.number(90)],driver:16)]
        for offset in [0.0,10,0,10,11,10] {
            let sample=TelemetryState.resolve(rows,driver:4,at:start.addingTimeInterval(offset))
            XCTAssertEqual(sample?.speed,offset<10 ? 101:220);XCTAssertEqual(sample?.gear,offset<10 ? 3:6)
            XCTAssertEqual(sample?.rpm,offset<10 ? 9000:12000);XCTAssertEqual(sample?.throttle,offset<10 ? 80:100)
            XCTAssertEqual(sample?.brake,offset<10 ? 0:100);XCTAssertEqual(sample?.drs,offset<10 ? 12:0)
        }
        XCTAssertNil(TelemetryState.resolve(rows,driver:4,at:start.addingTimeInterval(-1)))
        XCTAssertNil(TelemetryState.resolve(rows,driver:4,at:start.addingTimeInterval(14)))
        XCTAssertNil(TelemetryState.resolve(rows,driver:44,at:start.addingTimeInterval(10)))
        XCTAssertEqual(TelemetryState.resolve(rows,driver:16,at:start.addingTimeInterval(10))?.speed,90)
    }
    @MainActor func testDensityPersistsOverridesAndNeverChangesCars() {
        let suite="polish-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let layers=MapLayers(defaults:defaults);XCTAssertEqual(layers.density,.simple);XCTAssertFalse(layers.contains(.lightPanels))
        layers.set(.lightPanels,true);layers.density = .detailed;XCTAssertTrue(layers.contains(.cars))
        layers.density = .simple;XCTAssertTrue(layers.contains(.cars));XCTAssertTrue(layers.contains(.lightPanels))
        let restored=MapLayers(defaults:defaults);XCTAssertEqual(restored.density,.simple);XCTAssertTrue(restored.contains(.lightPanels))
    }
    func testLabelPlacementPreservesAnchorAndAvoidsCarsAndLabels() throws {
        let anchor=CGPoint(x:140,y:100);var occupied=[CGRect(x:130,y:90,width:20,height:20)]
        for _ in 0..<12 {if let rect=MapLabelLayout.place(anchor:anchor,size:.init(width:26,height:13),bounds:.init(width:300,height:220),occupied:&occupied,technical:true) {XCTAssertFalse(occupied.dropLast().contains{$0.intersects(rect)});XCTAssertNotEqual(CGPoint(x:rect.midX,y:rect.midY),anchor)}}
        XCTAssertEqual(anchor,CGPoint(x:140,y:100));XCTAssertGreaterThan(occupied.count,5)
    }
    func testFreshnessIsSourceAge() {let connection=ConnectionState(connected:true,lastReceived:start);XCTAssertEqual(connection.label(at:start.addingTimeInterval(2)),"LIVE · 2.0s");XCTAssertEqual(connection.label(at:start.addingTimeInterval(20)),"Waiting for data · 20s")}
    func testOpenF1CompletedPitTimestampNormalizesOnce() {
        let exit=start.addingTimeInterval(1900)
        let source=record("pit",1900,["date":.string(Dates.iso(exit)),"lane_duration":.number(1840.7)])
        let normalized=OpenF1HistoricalProvider.normalizedPit(source)
        XCTAssertEqual(normalized.date.timeIntervalSince(start),59.3,accuracy:0.001)
        XCTAssertEqual(OpenF1HistoricalProvider.normalizedPit(normalized).date,normalized.date)
        XCTAssertEqual(normalized.fields.s("date"),Dates.iso(exit))
    }
    @MainActor func testStintHistoryRetainsDistinctSetsPriorUsageAndCursorReconstruction() throws {
        let base=record("drivers",0,["full_name":.string("Driver")])
        let first=record("stints",0,["stint_number":.number(1),"lap_start":.number(1),"lap_end":.number(12),"compound":.string("SOFT"),"tyre_age_at_start":.number(0)])
        let second=record("stints",120,["stint_number":.number(2),"lap_start":.number(13),"lap_end":.number(27),"compound":.string("MEDIUM"),"tyre_age_at_start":.number(3)])
        let third=record("stints",270,["stint_number":.number(3),"lap_start":.number(28),"compound":.string("MEDIUM"),"tyre_age_at_start":.number(0)])
        for (cursor,count) in [(0.0,1),(120,2),(270,3),(0,1),(270,3),(120,2)] {
            let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.replay)
            store.ingest([base,first,second,third,third],through:start.addingTimeInterval(cursor))
            store.drivers[4]?.lastLap = .init(number:cursor>=270 ? 30:cursor>=120 ? 15:1,duration:10,sectors:[],speeds:[],segments:[],start:start)
            let driver=try XCTUnwrap(store.drivers[4]),rows=StintHistoryRow.rows(driver)
            XCTAssertEqual(rows.count,count);XCTAssertEqual(rows.filter(\.current).count,1);XCTAssertTrue(rows.last!.current)
            XCTAssertEqual(rows[0].raceLaps,count==1 ? 1:12)
            if count>1 {XCTAssertEqual(rows[1].prior,3);XCTAssertEqual(rows[0].range,"L1–12");XCTAssertFalse(rows[0].current)}
            if count==3 {XCTAssertEqual(rows[1].compound,rows[2].compound);XCTAssertNotEqual(rows[1].id,rows[2].id)}
            var stale=second;stale.id="stale";stale.date=start.addingTimeInterval(100);stale.fields["compound"] = .string("WET")
            if count>1 {store.ingest([stale]);XCTAssertEqual(store.drivers[4]?.stints.first{$0.id==2}?.compound,"MEDIUM")}
            let other=DriverState(id:16,name:"Other",acronym:"OTH",team:"",color:"888888")
            XCTAssertTrue(StintHistoryRow.rows(other).isEmpty)
        }
        XCTAssertEqual(L10n.text("Tyre history",language:"en"),"Tyre history")
        XCTAssertEqual(L10n.text("Tyre history",language:"ja"),"タイヤ履歴")
        XCTAssertEqual(L10n.text("Prior use",language:"ja"),"事前使用")
    }

    @MainActor func testFocusSwitchClearsTelemetryAndMockSeeksRebuildHistory() async throws {
        let model=AppModel(cachePath:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        model.loadMock();model.store.drivers[1]?.telemetry=MockF1Provider.telemetry(driver:4,time:model.clock.time)
        model.focusDriver(1);XCTAssertNil(model.store.drivers[1]?.telemetry)
        await model.refreshTelemetry();XCTAssertNotNil(model.store.drivers[1]?.telemetry)
        model.focusDriver(4);XCTAssertNil(model.store.drivers[4]?.telemetry)
        for offset in [200.0,10,200,10] {
            model.seek(MockF1Provider.start.addingTimeInterval(offset),resumePlaying:false)
            try await Task.sleep(for:.milliseconds(700))
            XCTAssertEqual(model.store.selected,4)
            XCTAssertEqual(model.store.drivers[4]?.telemetry?.date,model.clock.time)
            let rows=StintHistoryRow.rows(try XCTUnwrap(model.store.drivers[4]))
            XCTAssertEqual(rows.count,offset>100 ? 2:1)
        }
    }

    func testGeneratedEventCategoriesLocalizeFromFacts() {
        let facts=RaceEventFacts(fields:["lap_number":.number(12),"lap_duration":.number(81.2),"from_compound":.string("SOFT"),"to_compound":.string("HARD")],names:["Lando Norris"],japaneseNames:["ノリス"])
        for (category,raw) in [("PENALTY","CAR 1 (NOR) 5 SECOND TIME PENALTY"),("RED FLAG","RED FLAG"),("SAFETY CAR","SAFETY CAR DEPLOYED"),("INVESTIGATION","CAR 1 UNDER INVESTIGATION"),("TYRE CHANGE",""),("FASTEST LAP","")] {
            let en=facts.text(category:category,raw:raw,language:"en"),ja=facts.text(category:category,raw:raw,language:"ja")
            XCTAssertNotEqual(en,ja);XCTAssertFalse(en.unicodeScalars.contains{$0.value>=0x3000 && $0.value<=0x9fff})
        }
    }

    func testReplayCacheSkipsOldPositionsWithoutDroppingTimingFacts() async throws {
        let cache=try HistoricalCache(path:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        try await cache.write([record("pit",0,[:]),record("stints",0,[:]),record("location",0,[:]),record("location",20,[:]),record("car_data",20,[:])],session:1)
        let rows=try await cache.read(session:1,after:.distantPast,through:start.addingTimeInterval(30),rebuild:true,locationAfter:start.addingTimeInterval(10))
        XCTAssertEqual(Set(rows.map(\.kind)),["pit","stints","location"]);XCTAssertEqual(rows.count,3)
        XCTAssertEqual(rows.first{$0.kind=="location"}?.date,start.addingTimeInterval(20))
    }

    @MainActor func testSlowTelemetryNeverBlocksReplayAndDriverSwitchCancelsIt() async throws {
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[PendingTelemetryProtocol.self]
        let model=AppModel(cachePath:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,historicalTransport:URLSession(configuration:configuration))
        model.start();model.store.mode = .replay
        let chunk=Int(model.clock.time.timeIntervalSince1970/120)
        for c in chunk-1...chunk+1 {try await model.cache.mark("location:0:\(c)",session:MockF1Provider.session.id)}
        let before=model.clock.time;model.focusDriver(4)
        try await Task.sleep(for:.seconds(1))
        XCTAssertGreaterThan(model.clock.time.timeIntervalSince(before),0.4)
        XCTAssertNil(model.store.drivers[4]?.telemetry)
        model.focusDriver(1);XCTAssertNil(model.store.drivers[1]?.telemetry)
        model.dismissFocus();model.clock.playing=false
    }

    @MainActor func testResponseResolvesAdvancedCursorInsteadOfDiscardingOrPublishingOldSample() async throws {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[DelayedTelemetryProtocol.self]
        let model=AppModel(cachePath:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,historicalTransport:URLSession(configuration:config))
        model.loadMock();model.store.mode = .replay;model.clock.playing=false
        model.store.selected=4;model.store.currentTime=Date(timeIntervalSince1970:1001)
        let request=Task {await model.refreshTelemetry()}
        try await Task.sleep(for:.milliseconds(200))
        model.store.currentTime=Date(timeIntervalSince1970:1002)
        await request.value
        XCTAssertEqual(model.store.drivers[4]?.telemetry?.speed,102)
        XCTAssertEqual(model.store.drivers[4]?.telemetry?.date,model.store.currentTime)
        model.dismissFocus()
    }

    @MainActor func testDelayedTelemetryPublishesDuringPlaybackAndAcrossChunkBoundary() async throws {
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[DelayedTelemetryProtocol.self]
        let model=AppModel(cachePath:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,historicalTransport:URLSession(configuration:configuration))
        model.start();model.store.mode = .replay
        let cursor=Date(timeIntervalSince1970:1017)
        model.clock = .init(start:cursor,end:cursor.addingTimeInterval(300),time:cursor,speed:2,playing:true)
        model.store.currentTime=cursor
        for chunk in 7...12 {try await model.cache.mark("location:0:\(chunk)",session:MockF1Provider.session.id)}
        model.focusDriver(4);model.focusHovered=true
        defer {model.clock.playing=false;model.dismissFocus()}
        try await Task.sleep(for:.seconds(1))
        XCTAssertGreaterThan(model.clock.time,cursor)
        XCTAssertNotNil(model.store.drivers[4]?.telemetry,"A response must survive normal cursor advancement")
        for _ in 0..<10 {
            try await Task.sleep(for:.milliseconds(250))
            let t=try XCTUnwrap(model.store.drivers[4]?.telemetry)
            XCTAssertTrue(t.valid(at:model.store.currentTime))
            XCTAssertEqual(t.speed,Int(floor(model.store.currentTime.timeIntervalSince1970))%300)
            XCTAssertEqual(t.gear,4)
        }
        XCTAssertGreaterThan(model.store.currentTime.timeIntervalSince1970,1020)
        model.clock.playing=false
        let frozen=model.store.drivers[4]?.telemetry
        try await Task.sleep(for:.milliseconds(500))
        XCTAssertEqual(model.store.drivers[4]?.telemetry,frozen)
    }

    @MainActor func testCachedTelemetryDisplaysWhileNetworkIsPendingWithoutFutureLeak() async throws {
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[PendingTelemetryProtocol.self]
        let model=AppModel(cachePath:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,historicalTransport:URLSession(configuration:configuration))
        model.loadMock();model.store.mode = .replay;model.clock.playing=false
        let cursor=model.clock.time
        try await model.cache.write([
            .init(id:"past",date:cursor.addingTimeInterval(-1),kind:"car_data",driver:4,fields:["speed":.number(123)]),
            .init(id:"future",date:cursor.addingTimeInterval(1),kind:"car_data",driver:4,fields:["speed":.number(299)])
        ],session:MockF1Provider.session.id)
        model.focusDriver(4)
        try await Task.sleep(for:.milliseconds(300))
        XCTAssertEqual(model.store.drivers[4]?.telemetry?.speed,123)
        model.dismissFocus()
    }

}

final class PendingTelemetryProtocol:URLProtocol {
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {} // Deliberately pending until the selection cancels it.
    override func stopLoading() {}
}

final class DelayedTelemetryProtocol:URLProtocol {
    private var pending:DispatchWorkItem?
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        let items=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
        let start=Dates.parse(items.first{$0.name=="date>"}!.value!)!.timeIntervalSince1970
        let end=Dates.parse(items.first{$0.name=="date<"}!.value!)!.timeIntervalSince1970
        let driver=Int(items.first{$0.name=="driver_number"}!.value!)!
        let rows=(Int(start)+1..<Int(end)).map{t in ["date":Dates.iso(Date(timeIntervalSince1970:Double(t))),"driver_number":driver,"speed":t%300,"n_gear":4,"rpm":11000,"throttle":100,"brake":0,"drs":12] as [String:Any]}
        let data=try! JSONSerialization.data(withJSONObject:rows)
        let work=DispatchWorkItem {[weak self] in
            guard let self else{return}
            self.client?.urlProtocol(self,didReceive:HTTPURLResponse(url:self.request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
            self.client?.urlProtocol(self,didLoad:data);self.client?.urlProtocolDidFinishLoading(self)
        }
        pending=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.45,execute:work)
    }
    override func stopLoading() {pending?.cancel()}
}
