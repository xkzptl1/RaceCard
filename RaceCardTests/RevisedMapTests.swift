import XCTest
import RaceCardDataKit
@testable import RaceCard

final class RevisedMapTests:XCTestCase {
    func testPitFieldCombinationsAndLanguages() {
        for language in ["ja","en"] {
            for (stop,lane) in [(2.7 as Double?,22.8 as Double?),(nil,24.1),(2.7,nil),(nil,nil)] {
                let p=PitTimingPresentation(stopDuration:stop,laneDuration:lane,suspended:false)
                XCTAssertEqual(p.stopDuration,stop);XCTAssertEqual(p.laneDuration,lane)
                XCTAssertTrue(p.primary(language).contains(stop == nil ? (language=="ja" ? "不明":"unavailable"):"2.700"))
                XCTAssertFalse(p.primary(language).contains("22.800"));XCTAssertFalse(p.primary(language).contains("24.100"))
                if lane != nil {XCTAssertTrue(p.detail(language).contains(language=="ja" ? "ピットレーン滞在":"Pit-lane duration"))}
            }
        }
    }
    func testSuspensionNeverManufacturesStopTimeOrPerformance() {
        let t=Date(timeIntervalSince1970:1000)
        let inflated=PitState(id:"red",driver:43,lap:3,date:t,stopDuration:nil,laneDuration:1844.9)
        let factual=PitState(id:"real",driver:1,lap:3,date:t,stopDuration:2.7,laneDuration:1840.7)
        let normal=PitState(id:"normal",driver:2,lap:3,date:t,stopDuration:3.1,laneDuration:21)
        XCTAssertTrue(inflated.intersects([.init(start:t.addingTimeInterval(-30),end:t.addingTimeInterval(1800))]))
        XCTAssertNil(inflated.stopDuration)
        XCTAssertEqual(PitTimingPresentation.fastest([inflated,factual,normal])?.id,"real")
        XCTAssertNil(PitTimingPresentation.fastest([inflated]))
        for lang in ["en","ja"] {
            let p=PitTimingPresentation(stopDuration:inflated.stopDuration,laneDuration:inflated.laneDuration,suspended:true)
            XCTAssertFalse(p.primary(lang).contains("1844"));XCTAssertFalse(p.primary(lang).contains("30:"))
            XCTAssertTrue(p.detail(lang).contains("30:44.900"))
            XCTAssertTrue(PitTimingPresentation(stopDuration:2.7,laneDuration:1844.9,suspended:true).primary(lang).contains("2.700"))
        }
    }
    @MainActor func testRealMonzaColapintoRegressionAndReplayReconstruction() throws {
        let entry=Dates.parse("2026-09-06T13:08:31.540Z")!,exit=Dates.parse("2026-09-06T13:39:16.440Z")!
        let source=NormalizedRecord(id:"monza-colapinto",date:exit,kind:"pit",driver:43,fields:["date":.string("2026-09-06T13:39:16.440Z"),"lap_number":.number(3),"lane_duration":.number(1844.9),"stop_duration":.null])
        let normalized=OpenF1HistoricalProvider.normalizedPit(source)
        XCTAssertEqual(normalized.fields,source.fields.merging(["_pit_exit_date":.string(Dates.iso(exit)),"_pit_timestamp_source":.string("OpenF1 completed PitStop/PitLaneTimeCollection")]){_,new in new})
        XCTAssertEqual(normalized.date.timeIntervalSince(entry),0,accuracy:0.001)
        let red=NormalizedRecord(id:"red",date:Dates.parse("2026-09-06T13:07:43Z")!,kind:"race_control",driver:nil,fields:["message":.string("RED FLAG - RACE SUSPENDED"),"flag":.string("RED")])
        let roster=NormalizedRecord(id:"43",date:red.date.addingTimeInterval(-30),kind:"drivers",driver:43,fields:["full_name":.string("Franco Colapinto"),"name_acronym":.string("COL")])
        let store=RaceStateStore()
        for cursor in [entry.addingTimeInterval(10),entry.addingTimeInterval(-1),exit,entry.addingTimeInterval(10),exit] {
            store.reset(MockF1Provider.session,mode:.replay);store.ingest([roster,red,normalized],through:cursor);store.currentTime=cursor
            if cursor<entry {XCTAssertTrue(store.drivers[43]!.pits.isEmpty);continue}
            let pit=try XCTUnwrap(store.drivers[43]?.pits.first)
            XCTAssertEqual(pit.laneDuration,1844.9);XCTAssertNil(pit.stopDuration)
            XCTAssertEqual(store.pitState(store.drivers[43]!),cursor<exit ? .pitDuringSuspension:.outside)
            let event=try XCTUnwrap(store.events.first{$0.category=="PIT"})
            XCTAssertFalse(event.localizedText("en").contains("1844"));XCTAssertTrue(event.localizedText("ja").contains("赤旗中断中"));XCTAssertTrue(event.localizedDetail("en").contains("30:44.900"))
        }
    }
    @MainActor func testIndependentPitMetricsAcrossLanguagesSuspensionAndSeeks() throws {
        let entry=Date(timeIntervalSince1970:1000)
        for (stop,lane) in [(2.4 as Double?,22.8),(nil,22.8),(2.7,1844.9),(nil,1844.9)] {
            let suspended=lane>1800
            let roster=NormalizedRecord(id:"driver",date:entry.addingTimeInterval(-20),kind:"drivers",driver:43,fields:["full_name":.string("Franco Colapinto")])
            let pit=NormalizedRecord(id:"source-pit",date:entry,kind:"pit",driver:43,fields:["lap_number":.number(3),"stop_duration":stop.map{.number($0)} ?? .null,"lane_duration":.number(lane),"pit_duration":.number(9999)])
            let red=NormalizedRecord(id:"red",date:entry.addingTimeInterval(-10),kind:"race_control",driver:nil,fields:["flag":.string("RED"),"message":.string("RED FLAG")])
            let green=NormalizedRecord(id:"green",date:entry.addingTimeInterval(1800),kind:"race_control",driver:nil,fields:["message":.string("SESSION RESUMED")])
            let records=[roster,pit]+(suspended ? [red,green]:[])
            let store=RaceStateStore()
            for offset in [1.0,-1,1,lane+1,1] {
                store.reset(MockF1Provider.session,mode:.replay);store.ingest(records,through:entry.addingTimeInterval(offset));store.currentTime=entry.addingTimeInterval(offset)
                if offset<0 {XCTAssertNil(store.latestPit);XCTAssertEqual(store.pitState(store.drivers[43]!),.outside);continue}
                let normalized=try XCTUnwrap(store.latestPit)
                XCTAssertEqual(normalized.stopDuration,stop);XCTAssertEqual(normalized.laneDuration,lane)
                XCTAssertEqual(normalized.pitEntryTimestamp,entry)
                XCTAssertEqual(normalized.pitExitTimestamp,entry.addingTimeInterval(lane))
                XCTAssertEqual(store.drivers[43]?.pits.count,1)
                XCTAssertEqual(store.events.filter{$0.category=="PIT"}.count,1)
                XCTAssertEqual(store.pitState(store.drivers[43]!),offset>=lane ? .outside:suspended ? .pitDuringSuspension:.normalPit)
                let event=try XCTUnwrap(store.events.first{$0.category=="PIT"})
                for language in ["ja","en"] {
                    let timing=PitTimingPresentation(stopDuration:normalized.stopDuration,laneDuration:normalized.laneDuration,suspended:normalized.intersects(store.suspensions))
                    XCTAssertEqual(timing.suspended,suspended)
                    XCTAssertTrue(timing.service(language).contains(stop == nil ? (language=="ja" ? "不明":"unavailable"):String(format:"%.3f",stop!)))
                    XCTAssertFalse(timing.service(language).contains(String(format:"%.3f",lane)))
                    XCTAssertTrue(timing.detail(language).contains(language=="ja" ? "ピットレーン滞在":"Pit-lane duration"))
                    XCTAssertFalse(event.localizedText(language).contains("9999"))
                    if suspended {
                        XCTAssertFalse(event.localizedText(language).contains("1844"));XCTAssertFalse(event.localizedText(language).contains("30:44"))
                        XCTAssertTrue(event.localizedDetail(language).contains("30:44.900"))
                    } else {XCTAssertTrue(event.localizedText(language).contains("22.800"))}
                }
            }
        }
    }
    func testLegacyGenericDurationNeverBecomesEitherMetricOrAnEstimatedStop() {
        let reported=Date(timeIntervalSince1970:2000)
        let source=NormalizedRecord(id:"legacy",date:reported,kind:"pit",driver:43,fields:["date":.string(Dates.iso(reported)),"pit_duration":.number(1844.9)])
        let normalized=OpenF1HistoricalProvider.normalizedPit(source)
        XCTAssertEqual(normalized.date,reported)
        XCTAssertNil(normalized.fields.n("stop_duration"));XCTAssertNil(normalized.fields.n("lane_duration"))
        XCTAssertNil(normalized.fields.s("_pit_exit_date"))
    }
    func testFastestPitRanksOnlyStationaryServiceRegardlessOfLaneTime() {
        let entry=Date(timeIntervalSince1970:1000)
        let candidates=[
            PitState(id:"short-lane",driver:1,lap:1,date:entry,stopDuration:4,laneDuration:18),
            PitState(id:"fast-service",driver:2,lap:1,date:entry,stopDuration:2.4,laneDuration:22.8),
            PitState(id:"missing-service",driver:3,lap:1,date:entry,stopDuration:nil,laneDuration:1),
            PitState(id:"red-lane-only",driver:4,lap:1,date:entry,stopDuration:nil,laneDuration:1844.9)]
        XCTAssertEqual(PitTimingPresentation.fastest(candidates)?.id,"fast-service")
        XCTAssertNil(PitTimingPresentation.fastest(Array(candidates.suffix(2))))
    }
    func testImmutableAnchorsAcrossLayouts() {
        let source=[TrackPoint(x:0,y:0),.init(x:1,y:0),.init(x:1,y:1)],anchor=MapAnnotationAnchor(id:"LP11",canonicalCoordinate:.init(x:0.3,y:0.7))
        for size in [CGSize(width:330,height:220),CGSize(width:800,height:400),CGSize(width:330,height:220)] {
            let projection=MapProjection(points:source,size:size),destination=projection.point(anchor.canonicalCoordinate)
            var occupied=[CGRect(x:destination.x-10,y:destination.y-10,width:20,height:20)]
            _=MapLabelLayout.place(anchor:destination,size:.init(width:40,height:16),bounds:size,occupied:&occupied,technical:true)
            XCTAssertEqual(destination,projection.point(anchor.canonicalCoordinate));XCTAssertEqual(anchor.canonicalCoordinate,.init(x:0.3,y:0.7))
        }
    }
    func testProjectionNeverRotatesWhenDetailOrWindowChangesAspect() {
        let points:[TrackPoint]=[.init(x:0,y:0),.init(x:0.15,y:0.7),.init(x:0.9,y:1),.init(x:1,y:0.9)]
        let baseline=MapProjection(points:points,size:.init(width:840,height:480))
        for size in [CGSize(width:840,height:340),CGSize(width:840,height:240),CGSize(width:600,height:500),CGSize(width:600,height:240)] {
            let p=MapProjection(points:points,size:size)
            XCTAssertEqual(p.angle,baseline.angle)
            XCTAssertEqual(p.center,baseline.center)
            for point in points {
                let a=baseline.point(point),b=p.point(point)
                XCTAssertEqual((a.x-baseline.size.width/2)/baseline.scale,(b.x-size.width/2)/p.scale,accuracy:0.000001)
                XCTAssertEqual((a.y-baseline.size.height/2)/baseline.scale,(b.y-size.height/2)/p.scale,accuracy:0.000001)
            }
        }
    }
    func testSafetyPriority() {
        XCTAssertEqual(MapSafetyPriority.flag(phase:.red,flags:["YELLOW","DOUBLE YELLOW"]),"RED")
        XCTAssertEqual(MapSafetyPriority.flag(phase:.safetyCar,flags:["YELLOW","DOUBLE YELLOW"]),"DOUBLE YELLOW")
        XCTAssertEqual(MapSafetyPriority.flag(phase:.virtualSafetyCar,flags:["YELLOW"]),"YELLOW")
        XCTAssertNil(MapSafetyPriority.flag(phase:.green,flags:["CLEAR"]))
    }
    @MainActor func testTimingAndRaceControlScopeNeverLeak() {
        let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.replay)
        for (n,scope,flag) in [(1,"TimingSector","YELLOW"),(15,"Sector","DOUBLE YELLOW"),(15,"Sector","CLEAR")] {
            store.apply(.init(id:"\(n)-\(flag)",date:Date(),kind:"race_control",driver:nil,fields:["message":.string("\(flag) IN TRACK SECTOR \(n)"),"scope":.string(scope),"sector":.number(Double(n)),"flag":.string(flag)]))
        }
        XCTAssertEqual(store.raceControl.timingSectorFlags[1],"YELLOW");XCTAssertNil(store.raceControl.sectorFlags[1]);XCTAssertNil(store.raceControl.sectorFlags[15])
    }
    func testStartLightsAcrossSpeedAndRepeatedSeeking() {
        let t=Date(timeIntervalSince1970:1000)
        for speed in [1.0,2,5] {
            var clock=ReplayClock(start:t.addingTimeInterval(-50),end:t.addingTimeInterval(500),time:t.addingTimeInterval(-4),speed:speed,playing:true)
            for _ in 0..<3 {
                var start=RaceStartPresentation();start.factualAnchor=t
                clock.seek(t.addingTimeInterval(-4));start.advance(at:clock.time);XCTAssertEqual(start.lightState(at:clock.time)?.illuminated,5)
                clock.advance(4/speed);start.advance(at:clock.time);XCTAssertEqual(start.lightState(at:clock.time)?.illuminated,0)
                clock.advance(10/speed);XCTAssertNil(start.lightState(at:clock.time))
            }
        }
    }
    func testAllegationFinalFindingAndPostRaceAreSeparate() throws {
        let t=Date(timeIntervalSince1970:1000)
        func event(_ text:String,_ offset:Double)->StewardEvent {StewardEvent.normalize(.init(id:text,date:t.addingTimeInterval(offset),kind:"race_control",driver:43,fields:["message":.string(text),"incident_id":.string("official-incident-43")]))!}
        let initial=event("CAR 43 WILL BE INVESTIGATED AFTER THE RACE - PRACTICE START INFRINGEMENT",0)
        let final=event("REPRIMAND FOR CAR 43 - STARTING PROCEDURE INFRINGEMENT",10000)
        XCTAssertEqual(initial.compact,"POST")
        XCTAssertEqual(StewardTimeline.active([initial,final],driver:43,at:t).first?.reason?.code,"practiceStart")
        let decision=try XCTUnwrap(StewardTimeline.active([initial,final],driver:43,at:final.timestamp).first)
        XCTAssertEqual(decision.compact,"REP");XCTAssertEqual(decision.reason?.code,"startingProcedure");XCTAssertEqual(decision.initialAllegation?.code,"practiceStart")
        XCTAssertTrue(decision.text("en").contains("Initial allegation"));XCTAssertTrue(decision.text("ja").contains("当初の疑い"))
        XCTAssertEqual(initial.reason?.code,"practiceStart")
    }
    @MainActor func testSimultaneousYellowCannotDowngradeDoubleYellow() {
        for flags in [["YELLOW","DOUBLE YELLOW"],["DOUBLE YELLOW","YELLOW"]] {
            let store=RaceStateStore();store.reset(MockF1Provider.session,mode:.replay)
            let date=Date(timeIntervalSince1970:1000)
            for flag in flags {store.apply(.init(id:flag,date:date,kind:"race_control",driver:nil,fields:["scope":.string("Sector"),"sector":.number(15),"flag":.string(flag),"message":.string(flag+" IN TRACK SECTOR 15")]))}
            XCTAssertEqual(store.raceControl.sectorFlags[15],"DOUBLE YELLOW");XCTAssertEqual(store.raceControl.flag,"DOUBLE YELLOW")
            store.apply(.init(id:"clear",date:date.addingTimeInterval(1),kind:"race_control",driver:nil,fields:["scope":.string("Sector"),"sector":.number(15),"flag":.string("CLEAR"),"message":.string("CLEAR IN TRACK SECTOR 15")]))
            XCTAssertNil(store.raceControl.sectorFlags[15])
        }
    }
    func testVerifiedRestartFormationDoesNotReuseOriginalLightAnchor() {
        let t=Date(timeIntervalSince1970:1000);var start=RaceStartPresentation();start.factualAnchor=t
        start.advance(at:t.addingTimeInterval(10));start.ingest(message:"EXTRA FORMATION LAP",lightCount:nil,confirmedStart:false,at:t.addingTimeInterval(100))
        start.advance(at:t.addingTimeInterval(101));XCTAssertEqual(start.phase,.formationLap);XCTAssertNil(start.lightState(at:t.addingTimeInterval(101)))
    }
    func testInitialStintDoesNotLeakIntoPreRaceHistory() {
        let session=MockF1Provider.session,t=session.start.addingTimeInterval(60)
        let lap=NormalizedRecord(id:"l1",date:t.addingTimeInterval(90),kind:"laps",driver:4,fields:["lap_number":.number(1),"date_start":.string(Dates.iso(t)),"lap_duration":.number(90)])
        let stint=NormalizedRecord(id:"s1",date:session.start,kind:"stints",driver:4,fields:["stint_number":.number(1),"lap_start":.number(1),"compound":.string("SOFT")])
        XCTAssertEqual(OpenF1HistoricalProvider.normalizedStints([stint],laps:[lap],pits:[],session:session).first?.date,t)
    }
}
