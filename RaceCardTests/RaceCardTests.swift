import XCTest
import SwiftUI
import AppKit
@testable import RaceCard

final class RaceCardTests: XCTestCase {
    let session = MockF1Provider.session
    func testMapperHandlesMixedValuesAndLapCompletionTime() throws {
        let data = Data(#"[{"driver_number":4,"lap_number":3,"date_start":"2025-06-15T10:00:00+00:00","lap_duration":90.5,"gap_to_leader":"+1 LAP"}]"#.utf8)
        let row = try XCTUnwrap(OpenF1Mapper.rows(data).first)
        let r = OpenF1Mapper.map("laps",row,session:session)
        XCTAssertEqual(r.driver,4); XCTAssertEqual(r.date.timeIntervalSince(Dates.parse(row.s("date_start"))!),90.5,accuracy:0.001); XCTAssertEqual(Timing.gap(row["gap_to_leader"]),"+1 LAP")
    }
    func testMQTTOrderingAndKeyReplacement() {
        var ledger = RecordLedger()
        var r = OpenF1Mapper.map("laps",["_key":.string("lap4"),"_id":.number(20)],session:session)
        XCTAssertTrue(ledger.accept(r)); XCTAssertFalse(ledger.accept(r)); r.order = 19; XCTAssertFalse(ledger.accept(r)); r.order = 21; XCTAssertTrue(ledger.accept(r))
    }
    @MainActor func testEventDeduplicationAndReplacement() {
        let store = RaceStateStore(); store.reset(session,mode:.live)
        var r = OpenF1Mapper.map("race_control",["_key":.string("flag"),"_id":.number(1),"flag":.string("YELLOW"),"message":.string("YELLOW FLAG")],session:session)
        store.apply(r); store.apply(r); XCTAssertEqual(store.events.count,1)
        r.order = 2; r.fields["message"] = .string("YELLOW FLAG SECTOR 2"); store.apply(r); XCTAssertEqual(store.events.count,1); XCTAssertTrue(store.events[0].text.contains("RC2")); XCTAssertTrue(store.events[0].rawMessage?.contains("SECTOR 2") ?? false)
    }
    func testFactuality() {
        XCTAssertEqual(EventNormalizer.classification("CAR 4 STOPPED"),"CAR STOPPED")
        XCTAssertEqual(EventNormalizer.classification("CAR 4 LOST POSITIONS"),"RACE CONTROL")
        XCTAssertEqual(EventNormalizer.classification("ENGINE FAILURE CAR 4"),"MECHANICAL")
        XCTAssertEqual(EventNormalizer.classification("DRS DISABLED"),"DRS DISABLED")
        XCTAssertEqual(EventNormalizer.classification("SAFETY CAR DEPLOYED"),"SAFETY CAR")
        XCTAssertEqual(EventNormalizer.classification("SAFETY CAR IN THIS LAP"),"SAFETY CAR")
        XCTAssertEqual(EventNormalizer.classification("SESSION STOPPED"),"SUSPENDED")
        XCTAssertEqual(EventNormalizer.overtake(corroboratedOnTrack:false),"POSITION CHANGE")
        XCTAssertEqual(EventNormalizer.overtake(corroboratedOnTrack:true),"OVERTAKE")
    }
    func testChampionshipDelta() { let e = ChampionshipEntry(id:"4",name:"NOR",before:100,current:125,rankBefore:2,rankCurrent:1); XCTAssertEqual(e.delta,25); XCTAssertEqual(e.rankBefore,2); XCTAssertEqual(e.rankCurrent,1) }
    func testReplayClockSpeedSeekAndEnd() {
        for speed in [1.0,2,5,10,50] { var c = ReplayClock(start:session.start,end:session.end,time:session.start,speed:speed,playing:true); c.advance(2); XCTAssertEqual(c.time.timeIntervalSince(session.start),2*speed); c.seek(session.start.addingTimeInterval(-10)); XCTAssertEqual(c.time,session.start); c.seek(session.end); c.advance(1); XCTAssertFalse(c.playing) }
    }
    func testLapOneUsesSourceStartAndSafeFallback() {
        let start = session.start.addingTimeInterval(45)
        let first = OpenF1Mapper.map("laps",["lap_number":.number(1),"date_start":.string(Dates.iso(start)),"lap_duration":.number(90)],session:session)
        let second = OpenF1Mapper.map("laps",["lap_number":.number(2),"date_start":.string(Dates.iso(start.addingTimeInterval(90))),"lap_duration":.number(90)],session:session)
        XCTAssertEqual(ReplayClock.firstLapStart(session:session,laps:[second,first]),start)
        XCTAssertEqual(ReplayClock.firstLapStart(session:session,laps:[second]),session.start)
    }
    @MainActor func testLanguageResourcesAndPersistence() {
        let old = Localization.shared.language
        defer { Localization.shared.language = old }
        Localization.shared.language = "ja"
        XCTAssertEqual(UserDefaults.standard.string(forKey:"language"),"ja")
        XCTAssertEqual(L10n.text("Play"),"再生")
        XCTAssertEqual(L10n.text("Lap 12"),"12周目")
        XCTAssertEqual(L10n.text("Fetching race control…"),"レースコントロールを取得中…")
        XCTAssertEqual(L10n.text("CAR 4 STOPPED AT TURN 2"),"CAR 4 STOPPED AT TURN 2")
        Localization.shared.language = "en"
        XCTAssertEqual(L10n.text("Play"),"Play")
    }
    func testStaleConnection() { var c = ConnectionState(); XCTAssertEqual(c.label(at:session.start),"NO DATA"); c.connected = true; c.lastReceived = session.start; XCTAssertTrue(c.label(at:session.start.addingTimeInterval(12)).contains("Waiting for data")); c.reconnecting = true; XCTAssertEqual(c.label(at:session.start),"RECONNECTING…") }
    func testReconnectBackoff() { var p = ReconnectPolicy(); XCTAssertEqual((0..<8).map { _ in p.nextDelay() },[1,2,4,8,16,32,60,60]); p.reset(); XCTAssertEqual(p.nextDelay(),1) }
    @MainActor func testMockFullGridAndNoFutureEvents() {
        let store = RaceStateStore(); store.reset(session,mode:.mock); let records = MockF1Provider.records()
        store.ingest(records.filter { $0.date <= session.start.addingTimeInterval(60) }); XCTAssertEqual(store.drivers.count,22); XCTAssertNotNil(store.weather); XCTAssertNotNil(store.fastest); XCTAssertTrue(store.events.allSatisfy { $0.date <= session.start.addingTimeInterval(60) }); XCTAssertFalse(store.events.contains { $0.category == "PIT" })
        store.ingest(records.filter { $0.date > session.start.addingTimeInterval(60) && $0.date <= session.start.addingTimeInterval(150) }); XCTAssertNotNil(store.latestPit); XCTAssertEqual(store.drivers[7]?.status,"STOPPED"); XCTAssertEqual(store.drivers[4]?.stints.count,2)
    }
    @MainActor func testOfficialStatusOnlyFromResults() {
        let store = RaceStateStore(); store.reset(session,mode:.historical)
        store.ingest(MockF1Provider.records().filter { $0.date == session.start })
        store.apply(OpenF1Mapper.map("position",["driver_number":.number(4),"position":.number(20)],session:session)); XCTAssertNil(store.drivers[4]?.status)
        store.apply(OpenF1Mapper.map("session_result",["driver_number":.number(4),"dnf":.bool(true),"position":.number(20)],session:session)); XCTAssertEqual(store.drivers[4]?.status,"DNF")
    }
    func testCachePersistenceRangeAndReplacement() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let c = try HistoricalCache(path:path); var records = MockF1Provider.records().filter { $0.date <= session.start.addingTimeInterval(5) }
        try await c.write(records,session:-1); try await c.mark("demo",session:-1); let count = try await c.count(session:-1); XCTAssertEqual(count,Set(records.map(\.id)).count)
        records[0].fields["test"] = .string("updated"); try await c.write([records[0]],session:-1)
        let reopened = try HistoricalCache(path:path); let covered = try await reopened.has("demo",session:-1); XCTAssertTrue(covered)
        let rows = try await reopened.read(session:-1,after:session.start,through:session.start.addingTimeInterval(2)); XCTAssertTrue(rows.allSatisfy { $0.date > session.start && $0.date <= session.start.addingTimeInterval(2) })
    }
    @MainActor func testCachedReplayThroughStore() async throws {
        let c = try HistoricalCache(path:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        try await c.write(MockF1Provider.records(),session:-1)
        let rows = try await c.read(session:-1,after:.distantPast,through:session.start.addingTimeInterval(100)); let store = RaceStateStore(); store.reset(session,mode:.replay); store.ingest(rows)
        XCTAssertEqual(store.drivers.count,22); XCTAssertNotNil(store.latestPit); XCTAssertFalse(store.events.contains { $0.category == "CAR STOPPED" })
    }
    func testTokenRefreshWithMockHTTP() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TokenURLProtocol.self]
        let manager = TokenManager(transport:URLSession(configuration:config),credentials:{ .init(username:"test+name@example.com",password:"test & value") })
        let first = try await manager.access(now:session.start); XCTAssertEqual(first,"unit-test-token")
        let expiry1 = await manager.expiry; _ = try await manager.access(now:session.start.addingTimeInterval(100)); let expiry2 = await manager.expiry; XCTAssertEqual(expiry1,expiry2)
        _ = try await manager.access(now:session.start.addingTimeInterval(3500)); let expiry3 = await manager.expiry; XCTAssertGreaterThan(expiry3,expiry2)
    }
    func testDisconnectedBrokerRetries() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TokenURLProtocol.self]
        let tokens = TokenManager(transport:URLSession(configuration:config),credentials:{ .init(username:"test",password:"test") }); let broker = DisconnectedBroker()
        let live = OpenF1LiveProvider(tokens:tokens,broker:broker)
        let task = Task { await live.run(session:session,telemetry:false,receive:{ _ in },status:{ _ in }) }
        try await Task.sleep(for:.milliseconds(1350)); task.cancel(); await task.value
        let attempts = await broker.attempts; XCTAssertGreaterThanOrEqual(attempts,2)
    }
    @MainActor func testFeedPreservesReadingAnchorAndNewCount() {
        func event(_ n: Int) -> FeedEvent { FeedEvent(id:String(n),date:session.start.addingTimeInterval(Double(n)),category:"RACE CONTROL",text:"Message \(n)") }
        let first = (0..<100).reversed().map(event)
        let view = NativeFeed(events:first,jump:0,unread:.constant(0))
        let coordinator = NativeFeed.Coordinator(view)
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:450,height:150))
        let table = NSTableView(frame:NSRect(x:0,y:0,width:450,height:5100)); table.headerView = nil; table.rowHeight = 51; table.intercellSpacing = .zero; table.addTableColumn(NSTableColumn(identifier:.init("event"))); table.dataSource = coordinator; table.delegate = coordinator
        scroll.documentView = table; coordinator.table = table; coordinator.scroll = scroll
        coordinator.update(view)
        scroll.contentView.scroll(to:NSPoint(x:0,y:510))
        let originalRow = table.row(at:NSPoint(x:1,y:scroll.contentView.bounds.minY+1))
        let anchor = coordinator.events[originalRow].id
        coordinator.update(NativeFeed(events:[event(100)]+first,jump:0,unread:.constant(0)))
        XCTAssertEqual(coordinator.count,1)
        let visible = table.row(at:NSPoint(x:1,y:scroll.contentView.bounds.minY+1))
        XCTAssertEqual(coordinator.events[visible].id,anchor)
        coordinator.update(NativeFeed(events:[event(100)]+first,jump:1,unread:.constant(0)))
        XCTAssertEqual(scroll.contentView.bounds.minY,0,accuracy:1); XCTAssertEqual(coordinator.count,0)
    }
    @MainActor func testMissingDataAndLiveOrdering() {
        let store = RaceStateStore(); store.reset(session,mode:.live)
        XCTAssertNil(store.weather); XCTAssertTrue(store.leaderboard.isEmpty); XCTAssertNil(store.fastest)
        store.apply(OpenF1Mapper.map("drivers",["driver_number":.number(4),"name_acronym":.string("NOR")],session:session))
        store.apply(OpenF1Mapper.map("position",["driver_number":.number(4),"position":.number(1),"_id":.number(20)],session:session))
        store.apply(OpenF1Mapper.map("position",["driver_number":.number(4),"position":.number(5),"_id":.number(19)],session:session))
        XCTAssertEqual(store.drivers[4]?.position,1)
        store.apply(OpenF1Mapper.map("laps",["driver_number":.number(4),"lap_number":.number(1),"lap_duration":.number(95)],session:session))
        store.apply(OpenF1Mapper.map("laps",["driver_number":.number(4),"lap_number":.number(2),"lap_duration":.null],session:session))
        XCTAssertEqual(store.drivers[4]?.lastLap?.number,1)
        XCTAssertEqual(store.drivers[4]?.lastLap?.duration,95)
    }
    func testRealHistoricalSessionFetch() async throws {
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent(Product.name)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let c = try HistoricalCache(path:folder.appendingPathComponent("history.sqlite").path); let provider = OpenF1HistoricalProvider(cache:c)
        let real = try await provider.session(key:9165); XCTAssertEqual(real.id,9165); XCTAssertEqual(real.type,"Race"); XCTAssertFalse(real.isLive())
        let prepared = try await provider.prepare(real) { message in print("Historical integration: \(message)") }
        let initialStints = try await c.read(session:9165,after:.distantPast,through:real.start,kind:"stints")
        XCTAssertEqual(initialStints.count,0) // Scheduled start precedes the factual first race lap.
        let track = try await provider.circuit(prepared); XCTAssertGreaterThan(track.count,100)
        let laps = try await c.read(session:9165,after:.distantPast,through:real.end,kind:"laps")
        XCTAssertGreaterThan(laps.count,500)
        let firstLapStart = ReplayClock.firstLapStart(session:real,laps:laps)
        let startedStints = try await c.read(session:9165,after:.distantPast,through:firstLapStart,kind:"stints")
        XCTAssertEqual(startedStints.count,19)
        let activeEnd = try XCTUnwrap(laps.map(\.date).max())
        try await provider.locations(prepared,from:activeEnd.addingTimeInterval(-120),through:activeEnd)
        let rows = try await c.read(session:9165,after:.distantPast,through:real.end,limit:10000)
        let drivers = rows.filter { $0.kind == "drivers" }; XCTAssertEqual(drivers.count,19) // Stroll did not participate in this race.
        let state = await MainActor.run { RaceStateStore() }
        await MainActor.run { state.reset(prepared,mode:.historical) }
        var offset = 0
        while true { let batch = try await c.read(session:9165,after:.distantPast,through:real.end,limit:5000,offset:offset); await MainActor.run { state.ingest(batch) }; if batch.count < 5000 { break }; offset += batch.count }
        await MainActor.run { XCTAssertEqual(state.drivers.count,19); XCTAssertTrue(state.official); XCTAssertNotNil(state.weather); XCTAssertNotNil(state.fastest); XCTAssertNotNil(state.latestPit); XCTAssertEqual(state.leaderboard.first?.acronym,"SAI"); XCTAssertTrue(state.drivers.values.contains { $0.location != nil }) }
        let lap = try XCTUnwrap(laps.first { ($0.fields.i("lap_number") ?? 0) == 2 })
        let at = try XCTUnwrap(Dates.parse(lap.fields.s("date_start"))).addingTimeInterval(30)
        try await provider.locations(prepared,from:at,through:at.addingTimeInterval(10))
        let a = try await c.read(session:9165,after:at,through:at.addingTimeInterval(1),kind:"location")
        let b = try await c.read(session:9165,after:at.addingTimeInterval(9),through:at.addingTimeInterval(10),kind:"location")
        XCTAssertFalse(a.isEmpty); XCTAssertFalse(b.isEmpty); XCTAssertNotEqual(a.first?.fields["x"],b.first?.fields["x"])
    }
}
final class TokenURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { let response = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!; client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed); client?.urlProtocol(self,didLoad:Data(#"{"access_token":"unit-test-token","expires_in":"3600"}"#.utf8)); client?.urlProtocolDidFinishLoading(self) }
    override func stopLoading() {}
}
actor DisconnectedBroker: BrokerTransport {
    var attempts = 0
    func consume(token:String,topics:[String],receive:@escaping @Sendable (LivePacket) async -> Void,connected:@escaping @Sendable () async -> Void) async throws { attempts += 1; throw URLError(.cannotConnectToHost) }
}
