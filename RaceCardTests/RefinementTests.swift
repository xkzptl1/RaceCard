import XCTest
import AppKit
import SwiftUI
@testable import RaceCard

final class RefinementTests: XCTestCase {
    let session = MockF1Provider.session
    func testJapaneseFactualTemplates() {
        let cases:[(String,String,String)] = [("SAFETY CAR","SAFETY CAR DEPLOYED","セーフティカー導入"),("VSC","VIRTUAL SAFETY CAR DEPLOYED","バーチャルセーフティカー導入"),("VSC","VIRTUAL SAFETY CAR ENDING","バーチャルセーフティカー終了予定"),("YELLOW FLAG","YELLOW FLAG IN TRACK SECTOR 2","RC2で黄旗"),("DOUBLE YELLOW","DOUBLE YELLOW IN TRACK SECTOR 2","RC2でダブルイエロー"),("DRS ENABLED","DRS ENABLED","DRS使用可能"),("DRS DISABLED","DRS DISABLED","DRS使用停止"),("CAR STOPPED","CAR 14 STOPPED","14号車が停止"),("PENALTY","CAR 1 - 5 SECOND TIME PENALTY","1号車に5秒ペナルティ")]
        for (category,raw,expected) in cases { XCTAssertEqual(JapaneseRaceText.text(category:category,raw:raw,driver:nil),expected) }
        XCTAssertEqual(JapaneseRaceText.text(category:"RACE CONTROL",raw:"UNRECOGNIZED CONTROL 42",driver:nil),"レースコントロール通知")
        XCTAssertEqual(EventNormalizer.classification("CHEQUERED FLAG",flag:"CHEQUERED"),"SESSION END")
        XCTAssertEqual(EventNormalizer.classification("CAR 14 LOST POSITIONS"),"RACE CONTROL")
        XCTAssertEqual(EventNormalizer.classification("CAR 14 INCIDENT NOTED"),"RACE CONTROL")
        XCTAssertEqual(EventNormalizer.classification("VIRTUAL SAFETY CAR ENDED"),"RESTART")
        XCTAssertEqual(JapaneseRaceText.text(category:"GREEN",raw:"PIT EXIT OPEN",driver:nil),"ピット出口開放")
        XCTAssertEqual(JapaneseRaceText.text(category:"PENALTY SERVED",raw:"CAR 4 PENALTY SERVED",driver:nil),"4号車がペナルティを消化")
    }
    @MainActor func testPositionMovesAreBatchedAndExpireWithoutFeedSpam() {
        let store=RaceStateStore();store.reset(session,mode:.mock)
        let records=MockF1Provider.records();store.ingest(records.filter{$0.date<=session.start})
        let count=store.events.count
        store.ingest(records.filter{$0.kind=="position" && $0.date==session.start.addingTimeInterval(12)})
        XCTAssertEqual(store.drivers[4]?.positionDelta,-2)
        XCTAssertEqual(store.drivers[81]?.positionDelta,3)
        XCTAssertEqual(store.drivers[4]?.movement(at:Date().addingTimeInterval(5)),0)
        store.ingest(records.filter{$0.kind=="overtakes"})
        XCTAssertEqual(store.events.count,count)
        XCTAssertFalse(store.events.contains{$0.category=="POSITION CHANGE"})
    }
    @MainActor func testStatusPriorityAndExplicitPenalties() throws {
        let store=RaceStateStore();store.reset(session,mode:.mock);store.ingest(MockF1Provider.records().filter{$0.date<=session.start})
        func control(_ text:String,_ t:Double) { store.ingest([OpenF1Mapper.map("race_control",["message":.string(text),"date":.string(Dates.iso(session.start.addingTimeInterval(t)))],session:session)]) }
        control("CAR 4 - 5 SECOND TIME PENALTY",1)
        var d=try XCTUnwrap(store.drivers[4]);XCTAssertEqual(d.penalty,"+5s")
        var rail=StatusRail.resolve(driver:d,state:"PIT",drsEnabled:true,precision:3,isRace:true)
        XCTAssertEqual(rail.pill,"+5s");XCTAssertFalse(rail.replacesGap)
        rail=StatusRail.resolve(driver:d,state:"STOPPED",drsEnabled:true,precision:3,isRace:true);XCTAssertEqual(rail.pill,"STOP");XCTAssertTrue(rail.replacesGap)
        control("CAR 4 PENALTY SERVED",2);d=try XCTUnwrap(store.drivers[4]);XCTAssertNil(d.penalty)
        XCTAssertEqual(StatusRail.resolve(driver:d,state:"PIT",drsEnabled:true,precision:3,isRace:true).pill,"PIT")
        d.investigation=true;XCTAssertEqual(StatusRail.resolve(driver:d,state:nil,drsEnabled:true,precision:3,isRace:true).pill,"INV")
        d.investigation=false;d.telemetry=MockF1Provider.telemetry(driver:4,time:session.start)
        XCTAssertEqual(StatusRail.resolve(driver:d,state:nil,drsEnabled:true,precision:3,isRace:true).pill,"DRS")
        XCTAssertNil(StatusRail.resolve(driver:d,state:nil,drsEnabled:false,precision:3,isRace:true).pill)
    }
    @MainActor func testMajorNoticeDedupExpiryAndPersistentPhase() {
        let store=RaceStateStore();store.reset(session,mode:.mock)
        func row(_ key:String,_ message:String,_ t:Double)->NormalizedRecord { OpenF1Mapper.map("race_control",["_key":.string(key),"message":.string(message),"date":.string(Dates.iso(session.start.addingTimeInterval(t)))],session:session) }
        store.ingest([row("1","SAFETY CAR DEPLOYED",1),row("2","SAFETY CAR DEPLOYED",2)])
        XCTAssertEqual(store.notices.count,1);XCTAssertEqual(store.raceControl.phase,.safetyCar)
        store.advanceNotices(at:Date().addingTimeInterval(6));XCTAssertTrue(store.notices.isEmpty);XCTAssertEqual(store.raceControl.phase,.safetyCar)
        store.ingest([row("3","VIRTUAL SAFETY CAR DEPLOYED",10)]);XCTAssertEqual(store.raceControl.phase,.virtualSafetyCar)
        store.ingest([row("4","SESSION RESUMED",20)]);XCTAssertEqual(store.raceControl.phase,.green)
    }
    @MainActor func testSectorStateAndMetadataAreFactual() throws {
        let store=RaceStateStore();store.reset(session,mode:.mock)
        XCTAssertTrue(try XCTUnwrap(store.metadata).verified)
        let singapore=try XCTUnwrap(TrackMetadata.load(circuit:"Singapore",session:9165));XCTAssertEqual(singapore.sectors.map(\.number),[1,2,3]);XCTAssertTrue(singapore.drsZones.isEmpty);XCTAssertNil(TrackMetadata.load(circuit:"Singapore",session:9999))
        XCTAssertEqual(store.metadata?.sectors.map(\.number),[1,2,3]);XCTAssertFalse(store.metadata?.drsZones.isEmpty ?? true)
        store.ingest([OpenF1Mapper.map("race_control",["message":.string("YELLOW FLAG IN TRACK SECTOR 2"),"flag":.string("YELLOW"),"sector":.number(2)],session:session)])
        XCTAssertEqual(store.raceControl.sectorFlags[2],"YELLOW")
        store.ingest([OpenF1Mapper.map("race_control",["message":.string("GREEN LIGHT"),"flag":.string("GREEN"),"date":.string(Dates.iso(session.start.addingTimeInterval(2)))],session:session)])
        XCTAssertTrue(store.raceControl.sectorFlags.isEmpty)
        store.reset(SessionState(id:1,meeting:1,title:"Unknown",circuit:"Unknown",type:"Race",start:session.start,end:session.end),mode:.replay);XCTAssertNil(store.metadata)
    }
    func testCompoundGlyphInkIsCentered() {
        for letter in ["S","M","H","I","W"] {
            for side:CGFloat in [16,23] {
                let square = CGRect(x:0,y:0,width:side,height:side)
                let bounds = CompoundGlyph(letter:letter,fontSize:side == 16 ? 9 : 12).path(in:square).boundingRect
                XCTAssertGreaterThan(bounds.width,0,letter)
                XCTAssertEqual(bounds.midX,square.midX,accuracy:0.001,letter)
                XCTAssertEqual(bounds.midY,square.midY,accuracy:0.001,letter)
                XCTAssertTrue(square.contains(bounds),letter)
            }
        }
    }
    func testTyresAndTeamRegistry() {
        XCTAssertEqual(TyreCompound("SOFT").letter,"S");XCTAssertEqual(TyreCompound("HARD").letter,"H");XCTAssertEqual(TyreCompound(nil),.unknown)
        XCTAssertEqual(TeamAssetRegistry.resolve(season:2026,name:"Scuderia Ferrari"),TeamAssetRegistry.resolve(season:2026,name:"Ferrari"))
        XCTAssertNil(TeamAssetRegistry.resolve(season:2023,name:"Audi").asset)
        XCTAssertEqual(TeamAssetRegistry.resolve(season:2026,name:"Unknown Racing Team").monogram,"URT")
        for team in Set(MockF1Provider.teams) { let asset=TeamAssetRegistry.resolve(season:2026,name:team).asset;XCTAssertNotNil(asset,team);XCTAssertNotNil(asset.flatMap{NSImage(named:$0)},team) }
    }
    func testLayoutScalesAcrossBreakpoints() {
        let compact=CardLayout(width:600,height:760),regular=CardLayout(width:1000,height:950),wide=CardLayout(width:1500,height:1100)
        XCTAssertTrue(compact.compact);XCTAssertFalse(regular.compact);XCTAssertTrue(wide.wide)
        XCTAssertGreaterThan(regular.centralHeight,compact.centralHeight);XCTAssertGreaterThan(wide.centralHeight,regular.centralHeight)
        XCTAssertGreaterThan(wide.text,compact.text);XCTAssertGreaterThanOrEqual(compact.text,14);XCTAssertLessThanOrEqual(wide.text,19)
    }
    @MainActor func testNamesAndSeekRebuildSuppressNotices() async throws {
        let model=AppModel(cachePath:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        model.loadMock();let nor=try XCTUnwrap(model.store.drivers[4]);XCTAssertEqual(DriverNameResolver.japanese(nor),"ノリス");XCTAssertEqual(nor.name,"Lando Norris")
        model.seek(session.start.addingTimeInterval(60),resumePlaying:false)
        try await Task.sleep(for:.milliseconds(700))
        XCTAssertEqual(model.store.raceControl.phase,.safetyCar);XCTAssertTrue(model.store.notices.isEmpty)
        XCTAssertTrue(model.store.events.allSatisfy{$0.date<=model.clock.time});XCTAssertTrue(model.store.drivers.values.allSatisfy{$0.positionDelta==0})
    }
}
