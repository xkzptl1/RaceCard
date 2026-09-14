import XCTest
final class RevisedMapUITests:XCTestCase {
    @MainActor func ready(_ app:XCUIApplication) {
        expectation(for:NSPredicate{_,_ in app.buttons["playPause"].exists && app.buttons["playPause"].isEnabled && app.buttons["driver-43"].exists},evaluatedWith:app);waitForExpectations(timeout:120)
    }
    @MainActor func launch(_ cursor:String,_ language:String="en",_ theme:String="Light",_ wide:Bool=false)->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--historical","11361","--historical-cursor",cursor,"-language",language,"-theme",theme,"-mapDensity","Detailed","-mapOverride.cars","YES","-mapOverride.raceControl","YES","-mapOverride.lightPanels","YES","-mapOverride.straightMode","YES"]
        app.launch();app.activate();if !app.windows.firstMatch.waitForExistence(timeout:5){app.typeKey("n",modifierFlags:.command)};ready(app)
        let w=app.windows.firstMatch,f=w.frame,c=w.coordinate(withNormalizedOffset:CGVector(dx:1,dy:1)).withOffset(CGVector(dx:-2,dy:-2));c.press(forDuration:0.15,thenDragTo:c.withOffset(CGVector(dx:(wide ? 1200:700)-f.width,dy:932-f.height)))
        return app
    }
    @MainActor func shot(_ app:XCUIApplication,_ name:String) {Thread.sleep(forTimeInterval:0.5);let a=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    @MainActor func testMonzaSuspendedPitSummaryFamilyAndFocus() {
        for (language,theme) in [("en","Light"),("ja","Dark")] {
            let app=launch("2026-09-06T13:08:32Z",language,theme)
            let latest=app.descendants(matching:.any)["latestPitSummary"].firstMatch,fast=app.descendants(matching:.any)["fastestSummary"].firstMatch,weather=app.descendants(matching:.any)["weatherSummary"].firstMatch
            XCTAssertTrue(latest.exists);XCTAssertEqual(latest.frame.height,fast.frame.height,accuracy:2);XCTAssertEqual(latest.frame.height,weather.frame.height,accuracy:2)
            XCTAssertTrue(latest.debugDescription.contains(language=="ja" ? "停止時間 不明":"Stop time unavailable"))
            XCTAssertTrue(latest.debugDescription.contains(language=="ja" ? "赤旗中断中":"During red-flag suspension"))
            XCTAssertFalse(app.debugDescription.contains("CAR 55 (SAI) LAP DELETED"));XCTAssertTrue(app.debugDescription.contains(language=="ja" ? "トラックリミット違反":"Track limits"))
            XCTAssertFalse(latest.debugDescription.contains("1844"));shot(app,"revised full summary row red flag "+language+" "+theme)
            app.buttons["driver-43"].click();XCTAssertTrue(app.descendants(matching:.any)["focusedTelemetry"].waitForExistence(timeout:5))
            XCTAssertTrue(app.debugDescription.contains(language=="ja" ? "停止時間 不明":"Stop time unavailable"));shot(app,"revised suspended Colapinto history feed "+language)
            app.terminate()
        }
    }
    @MainActor func testRealStartLightsAndPreRaceSeeking() {
        let app=launch("2026-09-06T13:03:26.936Z")
        let lights=app.descendants(matching:.any)["startLightHousing"].firstMatch
        XCTAssertTrue(lights.exists);XCTAssertTrue(lights.label.contains("5 / 5"));XCTAssertTrue(String(describing:app.staticTexts["sessionStatus"].value).contains("Pre-race"));shot(app,"revised factual pre Lap1 all five lights")
        for _ in 0..<2 {
            app.buttons["+10s"].click();ready(app);XCTAssertFalse(lights.exists)
            app.buttons["−10s"].click();ready(app);XCTAssertTrue(lights.label.contains("5 / 5"))
        }
        app.menuButtons["lapSelector"].click();app.menuItems["Lap 1"].click();ready(app);shot(app,"revised factual Lap1 lights out")
        app.menuButtons["lapSelector"].click();app.menuItems["Before start"].click();ready(app);XCTAssertTrue(lights.label.contains("5 / 5"))
        for speed in ["2×","5×"] {
            app.popUpButtons["replaySpeed"].click();app.menuItems[speed].click();app.buttons["playPause"].click();expectation(for:NSPredicate{_,_ in !lights.exists},evaluatedWith:app);waitForExpectations(timeout:20);app.buttons["playPause"].click();XCTAssertFalse(lights.exists)
            app.menuButtons["lapSelector"].click();app.menuItems["Before start"].click();ready(app);XCTAssertTrue(lights.label.contains("5 / 5"))
        }
        app.menuButtons["lapSelector"].click();app.menuItems["Pre-race"].click();ready(app);XCTAssertTrue(String(describing:app.staticTexts["sessionStatus"].value).contains("Pre-race"));shot(app,"revised earliest factual pre-race events")
        app.terminate()
    }
    @MainActor func testRealSafetySegmentsAndHolisticStates() {
        for (cursor,name,wide) in [("2026-09-06T13:06:34Z","double yellow RC15",false),("2026-09-06T13:06:51Z","Safety Car",true),("2026-09-06T13:07:45Z","Red Flag",false),("2026-09-06T13:42:24Z","verified extra formation lap",false),("2026-09-06T14:22:09Z","penalty and prominent telemetry",true)] {
            let app=launch(cursor,"en",wide ? "Dark":"Light",wide)
            if name.contains("RC15") {XCTAssertTrue(app.descendants(matching:.any)["trackMap"].firstMatch.debugDescription.contains("RC15"))}
            shot(app,"revised full window "+name)
            if name.contains("telemetry") {app.buttons["driver-11"].click();app.buttons["closeFocus"].hover();shot(app,"revised large telemetry and full driver history");app.buttons["stewardDetails"].click();shot(app,"revised penalty and independent POST decision details")}
            app.terminate()
        }
    }
    @MainActor func testRealHamiltonDeletedLapBothLanguagesAndSeeking() {
        for language in ["en","ja"] {
            let app=launch("2026-09-06T13:59:00Z",language,language=="en" ? "Light":"Dark")
            app.buttons["driver-44"].click()
            XCTAssertFalse(app.debugDescription.contains(language=="ja" ? "ハミルトンのラップタイム抹消":"Lewis HAMILTON lap time deleted"))
            app.buttons[language=="ja" ? "+10秒":"+10s"].click();ready(app)
            app.buttons["driver-44"].click();app.buttons["closeFocus"].hover()
            XCTAssertTrue(app.debugDescription.contains("1:26.415"));XCTAssertTrue(app.debugDescription.contains("T5"))
            XCTAssertTrue(app.debugDescription.contains(language=="ja" ? "トラックリミット違反":"Track limits"))
            XCTAssertFalse(app.buttons["driver-44"].label.contains("+5s"));XCTAssertFalse(app.buttons["driver-44"].label.contains("INV"))
            XCTAssertGreaterThan(app.descendants(matching:.any)["eventFeed"].firstMatch.frame.height,65)
            shot(app,"revised real Hamilton deleted lap factual time reason T5 "+language)
            app.buttons[language=="ja" ? "−10秒":"−10s"].click();ready(app)
            app.buttons["driver-44"].click();XCTAssertFalse(app.debugDescription.contains(language=="ja" ? "ハミルトンのラップタイム抹消":"Lewis HAMILTON lap time deleted"))
            app.buttons[language=="ja" ? "+10秒":"+10s"].click();ready(app);app.buttons["driver-44"].click()
            XCTAssertTrue(app.debugDescription.contains("1:26.415"));shot(app,"revised deterministic deletion replay "+language)
            app.buttons["closeFocus"].click();XCTAssertFalse(String(describing:app.staticTexts["fastestSummaryValue"].value).contains("1:26.415"));shot(app,"revised fastest summary excludes Hamilton deleted lap "+language)
            app.terminate()
        }
    }
}

/// Release gates exercise the installed Release binary and the ordinary Historical provider.
final class Revised4ProductionUITests:XCTestCase {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("RaceCardRev4QA")
    @MainActor func ready(_ app:XCUIApplication) {
        expectation(for:NSPredicate {_,_ in app.buttons["playPause"].exists && app.buttons["playPause"].isEnabled && app.buttons["driver-63"].exists && app.buttons["driver-3"].exists},evaluatedWith:app)
        waitForExpectations(timeout:600)
    }
    @MainActor func launch(_ key:Int,_ cursor:String,_ language:String="en",_ theme:String="Dark",width:CGFloat=1200,height:CGFloat=1000,density:String="Detailed")->XCUIApplication {
        let app=XCUIApplication()
        app.launchArguments=["--historical",String(key),"--historical-cursor",cursor,"-language",language,"-theme",theme,"-mapDensity",density,"-mapOverride.cars","YES"]
        if density=="Detailed" {app.launchArguments += ["-mapOverride.raceControl","YES","-mapOverride.corners","YES","-mapOverride.lightPanels","YES"]}
        app.launch();app.activate();if !app.windows.firstMatch.waitForExistence(timeout:5){app.typeKey("n",modifierFlags:.command)};ready(app)
        let w=app.windows.firstMatch
        // Resize from exposed edges: a tall window's lower corner can be behind the Dock.
        let right=w.coordinate(withNormalizedOffset:CGVector(dx:1,dy:0.5)).withOffset(CGVector(dx:-1,dy:0))
        right.press(forDuration:0.15,thenDragTo:right.withOffset(CGVector(dx:width-w.frame.width,dy:0)))
        let top=w.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0)).withOffset(CGVector(dx:0,dy:1))
        top.press(forDuration:0.15,thenDragTo:top.withOffset(CGVector(dx:0,dy:w.frame.height-height)))
        let title=w.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0)).withOffset(CGVector(dx:0,dy:15))
        title.press(forDuration:0.15,thenDragTo:title.withOffset(CGVector(dx:40-w.frame.minX,dy:30-w.frame.minY)))
        app.buttons["playPause"].hover()
        XCTAssertEqual(w.frame.width,width,accuracy:4)
        XCTAssertEqual(w.frame.height,height,accuracy:4)
        return app
    }
    @MainActor func evidence(_ app:XCUIApplication,_ name:String) throws -> [String:String] {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        print("RACECARD_QA_ROOT "+root.path)
        // Capture the settled surface rather than an in-flight focus crossfade.
        RunLoop.current.run(until:Date().addingTimeInterval(0.5))
        let screenshot=app.windows.firstMatch.screenshot()
        try screenshot.pngRepresentation.write(to:root.appendingPathComponent(name+".png"))
        let attachment=XCTAttachment(screenshot:screenshot);attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
        let debug=app.debugDescription
        try debug.write(to:root.appendingPathComponent(name+".txt"),atomically:true,encoding:.utf8)
        let bounds=app.windows.firstMatch.frame
        let driverPattern = #"\{\{([0-9.-]+), ([0-9.-]+)\}, \{([0-9.-]+), ([0-9.-]+)\}\}.*identifier: '(driver-[0-9]+)'"#
        let driverRegex=try NSRegularExpression(pattern:driverPattern)
        let debugText=debug as NSString
        for match in driverRegex.matches(in:debug,range:NSRange(location:0,length:debugText.length)) {
            let bottom=Double(debugText.substring(with:match.range(at:2)))!+Double(debugText.substring(with:match.range(at:4)))!
            XCTAssertLessThanOrEqual(bottom,bounds.maxY+1,"Every leaderboard row must remain inside the window")
        }
        var labels:[String:String]=[:]
        // Read actual accessibility frames from one native window snapshot.
        let pattern = #"\{\{([0-9.-]+), ([0-9.-]+)\}, \{([0-9.-]+), ([0-9.-]+)\}\}.*identifier: '(staticLabel-[^']+)'"#
        let regex=try NSRegularExpression(pattern:pattern)
        let ns=debug as NSString
        for match in regex.matches(in:debug,range:NSRange(location:0,length:ns.length)) {
            let x=Double(ns.substring(with:match.range(at:1)))!,y=Double(ns.substring(with:match.range(at:2)))!
            let w=Double(ns.substring(with:match.range(at:3)))!,h=Double(ns.substring(with:match.range(at:4)))!
            labels[ns.substring(with:match.range(at:5))]=String(format:"%.3f,%.3f",x+w/2,y+h/2)
        }
        try JSONSerialization.data(withJSONObject:labels,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent(name+"-coordinates.json"))
        return labels
    }
    @MainActor func pitText(_ element:XCUIElement)->String {element.label+" "+(element.value as? String ?? "")}
    @MainActor func testHistoricalTelemetryPlaybackBuffer() throws {
        // Unmodified real OpenF1 cache: continuous windows around Monza laps 7 and 9.
        for (cursor,driver,name) in [("2026-09-06T13:47:56Z",63,"lap7-boundary"),("2026-09-06T13:50:58Z",43,"lap9-boundary")] {
            let app=launch(11361,cursor,"ja","Dark",width:900,height:1000)
            app.buttons["driver-\(driver)"].click();app.buttons["closeFocus"].hover()
            let speed=app.descendants(matching:.any)["telemetry-Speed"].firstMatch
            expectation(for:NSPredicate{_,_ in (speed.label+String(describing:speed.value)).contains("km/h")},evaluatedWith:app)
            waitForExpectations(timeout:10)
            let before=try evidence(app,"telemetry-266-"+name+"-paused")
            app.buttons["playPause"].click();app.buttons["closeFocus"].hover()
            for _ in 0..<4 {
                Thread.sleep(forTimeInterval:0.8)
                XCTAssertTrue((speed.label+String(describing:speed.value)).contains("km/h"))
            }
            app.buttons["playPause"].click();app.buttons["closeFocus"].hover()
            let after=try evidence(app,"telemetry-266-"+name+"-played")
            XCTAssertEqual(before,after)
            app.buttons["−10秒"].click();ready(app);app.buttons["closeFocus"].hover()
            // Lap 9's earlier cursor falls outside this archive's downloaded samples.
            // Returning forward must recover without showing a future sample in the gap.
            _=try evidence(app,"telemetry-266-"+name+"-backward")
            app.buttons["+10秒"].click();ready(app);app.buttons["closeFocus"].hover()
            expectation(for:NSPredicate{_,_ in (speed.label+String(describing:speed.value)).contains("km/h")},evaluatedWith:app)
            waitForExpectations(timeout:10)
            _=try evidence(app,"telemetry-266-"+name+"-restored")
            app.terminate()
        }
        let app=launch(11361,"2026-09-06T13:48:40Z","ja","Dark",width:900,height:1000)
        app.buttons["driver-63"].click();app.buttons["closeFocus"].hover()
        let status=app.staticTexts["telemetryLoadStatus"]
        expectation(for:NSPredicate{_,_ in status.exists && self.pitText(status).contains("一時制限")},evaluatedWith:app)
        waitForExpectations(timeout:20)
        _=try evidence(app,"telemetry-266-lap8-provider-restricted")
        app.terminate()
    }

    @MainActor func testPitMetricsRealProductionBothLanguages() throws {
        for language in ["ja","en"] {
            for (key,cursor,driver,name,service,lane,red) in [
                (11361,"2026-09-06T13:08:33Z",43,"monza-red",nil as String?,"30:44.900",true),
                (11361,"2026-09-06T13:56:15Z",30,"monza-normal",nil,"31.100",false),
                (11280,"2026-05-03T17:14:25Z",3,"miami-normal","2.400","22.547",false)] {
                let app=launch(key,cursor,language,"Dark",width:900,height:1000)
                let summary=app.staticTexts["latestPitStopDuration"]
                XCTAssertTrue(summary.exists)
                XCTAssertTrue(pitText(summary).contains(service ?? (language=="ja" ? "停止時間 不明":"Stop time unavailable")))
                XCTAssertFalse(pitText(summary).contains(lane))
                if !red {XCTAssertTrue(pitText(app.staticTexts["latestPitLaneDuration"]).contains(lane))}
                else {XCTAssertFalse(app.staticTexts["latestPitLaneDuration"].exists)}
                _=try evidence(app,"pit-266-"+name+"-"+language+"-summary-feed")
                app.buttons["driver-\(driver)"].click();app.buttons["closeFocus"].hover()
                let serviceView=app.staticTexts["focusedPitStopDuration"],laneView=app.staticTexts["focusedPitLaneDuration"]
                XCTAssertTrue(pitText(serviceView).contains(service ?? (language=="ja" ? "停止時間 不明":"Stop time unavailable")))
                XCTAssertTrue(pitText(laneView).contains(lane))
                XCTAssertTrue(pitText(laneView).contains(language=="ja" ? "ピットレーン滞在":"Pit-lane duration"))
                XCTAssertFalse(pitText(serviceView).contains(lane))
                let initialService=pitText(serviceView),initialLane=pitText(laneView)
                _=try evidence(app,"pit-266-"+name+"-"+language+"-focus")
                app.buttons[language=="ja" ? "−10秒":"−10s"].click();ready(app)
                if laneView.exists {XCTAssertNotEqual(pitText(laneView),initialLane)}
                app.buttons[language=="ja" ? "+10秒":"+10s"].click();ready(app);app.buttons["closeFocus"].hover()
                XCTAssertEqual(pitText(serviceView),initialService);XCTAssertEqual(pitText(laneView),initialLane)
                _=try evidence(app,"pit-266-"+name+"-"+language+"-reseek")
                // Lane occupancy ends at the factual exit, independent of the displayed service time.
                if !red {
                    for _ in 0..<3 {app.buttons[language=="ja" ? "+10秒":"+10s"].click();ready(app)}
                    XCTAssertFalse(app.buttons["driver-\(driver)"].label.contains("PIT"))
                    XCTAssertEqual(pitText(serviceView),initialService);XCTAssertEqual(pitText(laneView),initialLane)
                    _=try evidence(app,"pit-266-"+name+"-"+language+"-after-exit")
                }
                app.terminate()
            }
        }
    }

    @MainActor func testRedPitExitKeepsHistoricalDurationsWithoutCurrentPitStatus() throws {
        for language in ["ja","en"] {
            let app=launch(11361,"2026-09-06T13:39:20Z",language,"Dark",width:900,height:1000)
            XCTAssertFalse(app.buttons["driver-43"].label.contains("PIT"))
            app.buttons["driver-43"].click();app.buttons["closeFocus"].hover()
            XCTAssertFalse(app.staticTexts["focusedPitState"].exists)
            XCTAssertTrue(pitText(app.staticTexts["focusedPitStopDuration"]).contains(language=="ja" ? "停止時間 不明":"Stop time unavailable"))
            XCTAssertTrue(pitText(app.staticTexts["focusedPitLaneDuration"]).contains("30:44.900"))
            _=try evidence(app,"pit-266-monza-red-"+language+"-after-exit")
            app.terminate()
        }
    }

    @MainActor func testJapanesePitLaneHeaderLocalization() throws {
        let app=launch(11361,"2026-09-06T13:08:33Z","ja","Dark",width:900,height:1000)
        app.buttons["driver-43"].click();app.buttons["closeFocus"].hover()
        let state=app.staticTexts["focusedPitState"]
        XCTAssertTrue(pitText(state).contains("ピットレーン"))
        XCTAssertFalse(pitText(state).contains("Pit lane"))
        _=try evidence(app,"pit-266-monza-red-ja-focus")
        app.terminate()
    }

    @MainActor func testFiveCircuitStaticCoordinatesAndFloatingAlerts() throws {
        for (key,cursor,name) in [(11361,"2026-09-06T13:06:51Z","italy-sc"),(11353,"2026-08-23T13:05:30Z","netherlands-red"),(11234,"2026-03-08T04:19:10Z","australia-vsc"),(11315,"2026-06-28T13:15:00Z","austria"),(11280,"2026-05-03T17:12:17Z","miami-sc")] {
            let app=launch(key,cursor)
            let first=try evidence(app,name+"-a")
            XCTAssertGreaterThanOrEqual(first.count,3)
            let map=app.descendants(matching:.any)["mapContent"].firstMatch
            let original=map.frame
            if key != 11315 {
                let alert=app.descendants(matching:.any)["mapAlertArea"].firstMatch
                XCTAssertTrue(alert.exists);XCTAssertLessThan(alert.frame.width,map.frame.width*0.76)
                XCTAssertTrue(map.frame.contains(alert.frame));XCTAssertFalse(app.descendants(matching:.any)["racePhaseChip"].firstMatch.exists)
            }
            app.buttons["+10s"].click();ready(app)
            let second=try evidence(app,name+"-b")
            XCTAssertEqual(first,second,"Final rendered static positions must remain identical")
            XCTAssertEqual(map.frame.height,original.height,accuracy:0.1)
            if key != 11315 {XCTAssertFalse(app.descendants(matching:.any)["mapAlertArea"].firstMatch.exists);XCTAssertTrue(app.descendants(matching:.any)["racePhaseChip"].firstMatch.exists)}
            app.buttons["−10s"].click();ready(app)
            XCTAssertEqual(first,try evidence(app,name+"-rewind"))
            app.buttons["+10s"].click();ready(app)
            XCTAssertEqual(first,try evidence(app,name+"-forward"))
            app.terminate()
        }
    }
    @MainActor func testItalyLightsSummaryAndLanguages() throws {
        for (language,theme) in [("en","Light"),("ja","Dark")] {
            let app=launch(11361,"2026-09-06T13:03:26.936Z",language,theme,width:900)
            let lights=app.descendants(matching:.any)["startLightHousing"].firstMatch
            XCTAssertTrue(lights.label.contains("5 / 5"));_ = try evidence(app,"italy-prestart-"+language)
            for speed in ["1×","2×","5×"] {
                app.popUpButtons["replaySpeed"].click();app.menuItems[speed].click()
                app.buttons["playPause"].click()
                expectation(for:NSPredicate{_,_ in !lights.exists},evaluatedWith:app);waitForExpectations(timeout:20)
                app.buttons["playPause"].click();_ = try evidence(app,"italy-lights-out-"+language+"-"+speed)
                app.menuButtons["lapSelector"].click();app.menuItems[language=="en" ? "Before start":"スタート直前"].click();ready(app)
                XCTAssertTrue(lights.label.contains("5 / 5"))
            }
            app.buttons[language=="en" ? "+10s":"+10秒"].click();ready(app);XCTAssertFalse(lights.exists)
            app.buttons[language=="en" ? "−10s":"−10秒"].click();ready(app);XCTAssertTrue(lights.label.contains("5 / 5"))
            app.sliders.firstMatch.adjust(toNormalizedSliderPosition:0.5);ready(app)
            app.menuButtons["lapSelector"].click();app.menuItems[language=="en" ? "Before start":"スタート直前"].click();ready(app)
            XCTAssertTrue(lights.label.contains("5 / 5"))
            app.menuButtons["lapSelector"].click();app.menuItems[language=="en" ? "Lap 1":"1周目"].click();ready(app)
            XCTAssertTrue(lights.label.contains("0 / 5"));_ = try evidence(app,"italy-exact-anchor-"+language)
            app.terminate()
            let suspended=launch(11361,"2026-09-06T13:08:32Z",language,theme,width:900)
            let latest=suspended.descendants(matching:.any)["latestPitSummary"].firstMatch
            let fast=suspended.descendants(matching:.any)["fastestSummary"].firstMatch
            XCTAssertEqual(latest.frame.height,fast.frame.height,accuracy:1)
            XCTAssertTrue(latest.debugDescription.contains(language=="en" ? "Stop time unavailable":"停止時間 不明"))
            XCTAssertFalse(latest.debugDescription.contains("1844"))
            _ = try evidence(suspended,"italy-summary-"+language)
            suspended.terminate()
        }
    }
    @MainActor func testEndingRestartAndFormation() throws {
        for (key,cursor,name) in [(11361,"2026-09-06T13:34:02Z","italy-still-suspended"),(11361,"2026-09-06T13:39:02Z","italy-restarted"),(11361,"2026-09-06T13:42:24Z","italy-extra-formation"),(11353,"2026-08-23T13:33:02Z","netherlands-restarted"),(11234,"2026-03-08T04:23:13Z","australia-ending"),(11234,"2026-03-08T04:23:20Z","australia-resume"),(11280,"2026-05-03T17:24:14Z","miami-ending"),(11280,"2026-05-03T17:25:34Z","miami-resume")] {
            let app=launch(key,cursor)
            _ = try evidence(app,name)
            if name.contains("still-suspended") {XCTAssertTrue(app.debugDescription.contains("Session suspended"))}
            if name.contains("resume") {XCTAssertFalse(app.descendants(matching:.any)["racePhaseChip"].firstMatch.exists)}
            app.terminate()
        }
    }
}

extension Revised4ProductionUITests {
    @MainActor func testCanonicalProfilesAndResponsiveCards() throws {
        let app=launch(11361,"2026-09-06T13:59:10Z","en","Dark",width:1300)
        _ = try evidence(app,"italy-wide-summary-and-deletion")
        app.buttons["driver-44"].click();_ = try evidence(app,"italy-hamilton-deleted-lap-focus")
        XCTAssertTrue(app.debugDescription.contains("1:26.415"));XCTAssertTrue(app.debugDescription.contains("T5"))
        app.buttons["closeFocus"].click();app.buttons["flipCard"].click()
        XCTAssertTrue(app.staticTexts["backTitle"].waitForExistence(timeout:5))
        _ = try evidence(app,"italy-championship-canonical-images-logos")
        for driver in [63,12,3,16,22] {
            let row=app.buttons["driverProfile-\(driver)"]
            row.click();XCTAssertTrue(app.buttons["closeProfile"].waitForExistence(timeout:5))
            _ = try evidence(app,"italy-profile-\(driver)")
            app.buttons["closeProfile"].click()
        }
        app.terminate()
    }
    @MainActor func testCrossCircuitJapaneseLightAndSimpleDensity() throws {
        for (key,cursor,name) in [(11361,"2026-09-06T13:08:32Z","italy"),(11353,"2026-08-23T13:06:00Z","netherlands"),(11234,"2026-03-08T04:20:00Z","australia"),(11315,"2026-06-28T13:15:00Z","austria"),(11280,"2026-05-03T17:13:00Z","miami")] {
            let app=launch(key,cursor,"ja","Light",width:900)
            _ = try evidence(app,name+"-japanese-light")
            XCTAssertGreaterThan(app.descendants(matching:.any)["eventFeed"].firstMatch.frame.height,110)
            app.terminate()
        }
        let simple=launch(11315,"2026-06-28T13:15:00Z","en","Dark",width:900,density:"Simple")
        _ = try evidence(simple,"austria-simple-dense-cars")
        simple.terminate()
    }
}


extension Revised4ProductionUITests {
    @MainActor func testDashboardAndDriverDetailShareIdenticalMap() throws {
        for (key,cursor,name) in [(11361,"2026-09-06T13:05:30Z","italy"),(11353,"2026-08-23T13:06:00Z","netherlands"),(11234,"2026-03-08T04:20:00Z","australia"),(11315,"2026-06-28T13:15:00Z","austria"),(11280,"2026-05-03T17:13:00Z","miami")] {
            for (width,height) in [(1200.0,1410.0),(900.0,1000.0)] {
                let app=launch(key,cursor,"ja","Dark",width:width,height:height)
                let prefix="consistent-map-\(name)-\(Int(width))"
                let initial=try evidence(app,prefix+"-dashboard")
                let frame=app.descendants(matching:.any)["mapContent"].firstMatch.frame
                XCTAssertGreaterThan(initial.count,3)
                for driver in [63,3] {
                    app.buttons["driver-\(driver)"].click()
                    XCTAssertTrue(app.buttons["closeFocus"].waitForExistence(timeout:5))
                    XCTAssertEqual(initial,try evidence(app,prefix+"-driver-\(driver)"))
                    XCTAssertEqual(frame,app.descendants(matching:.any)["mapContent"].firstMatch.frame)
                }
                app.buttons["closeFocus"].click()
                XCTAssertEqual(initial,try evidence(app,prefix+"-returned"))
                app.terminate()
            }
        }
    }
}
