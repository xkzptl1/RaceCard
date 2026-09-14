import XCTest
final class QualifyingProductionUITests:XCTestCase {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("RaceCardQualifyingQA")
    @MainActor func ready(_ app:XCUIApplication) {
        expectation(for:NSPredicate {_,_ in app.buttons["playPause"].exists && app.buttons["playPause"].isEnabled && app.buttons["qualifyingDriver-63"].exists && app.buttons["qualifyingDriver-3"].exists},evaluatedWith:app)
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
        let driverPattern = #"\{\{([0-9.-]+), ([0-9.-]+)\}, \{([0-9.-]+), ([0-9.-]+)\}\}.*identifier: '(qualifyingDriver-[0-9]+)'"#
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
    struct Comparison:Decodable {
        let key:Int;let driver:Int;let phase:Int;let lap:Int;let start:String;let s1:String;let s2:String;let finish:String;let sectors:[Double];let duration:Double
    }
    func cases()throws->[Comparison] {try JSONDecoder().decode([Comparison].self,from:Data(contentsOf:URL(fileURLWithPath:"/private/tmp/RaceCardQualifyingRaw/cases.json")))}
    @MainActor func text(_ element:XCUIElement)->String {element.label+" "+String(describing:element.value ?? "")}
    @MainActor func testPrimaryMadridFirstWindow()throws {
        let app=launch(11365,"2026-09-12T14:13:05Z",width:1200)
        _=try evidence(app,"madrid-first-window")
        app.terminate()
    }
    @MainActor func testRawComparisonThreeDriversEachCircuit()throws {
        for key in [11365,11249,11349] {
            let selected=try cases().filter{$0.key==key && $0.phase==1}
            for (i,c) in selected.enumerated() {
                let app=launch(key,c.finish,i==1 ? "ja":"en",i==2 ? "Light":"Dark",width:1200)
                app.buttons["qualifyingDriver-\(c.driver)"].click()
                let card=app.descendants(matching:.any)["qualifyingCard-\(c.driver)"].firstMatch
                XCTAssertTrue(card.waitForExistence(timeout:5))
                for sector in 0..<3 {
                    let value=app.descendants(matching:.any)["qualifyingSector-\(c.driver)-\(sector+1)"].firstMatch
                    XCTAssertTrue(text(value).contains(String(format:"%.3f",c.sectors[sector])),text(value))
                }
                XCTAssertTrue(text(app.staticTexts["qualifyingTime-\(c.driver)"]).contains(String(format:"%d:%06.3f",Int(c.duration)/60,c.duration.truncatingRemainder(dividingBy:60))))
                _=try evidence(app,"raw-\(key)-driver-\(c.driver)-q1")
                app.terminate()
            }
        }
    }
    @MainActor func testPhaseAndPinsAllCircuits()throws {
        for (key,cursor) in [(11365,"2026-09-12T14:16:35Z"),(11249,"2026-03-28T06:16:35Z"),(11349,"2026-08-22T14:16:35Z")] {
            let app=launch(key,cursor,width:1200)
            let before=try evidence(app,"phase-\(key)-q1-near-cut")
            for slot in 0..<3 {
                app.menuButtons["qualifyingPin-\(slot)"].click()
                app.menuItems[["NOR","RUS","VER"][slot]].click()
                _=try evidence(app,"pins-\(key)-\(slot+1)")
            }
            app.buttons["+10s"].click();ready(app)
            let after=try evidence(app,"pins-\(key)-forward")
            XCTAssertEqual(before,after,"Static labels must not move with cars or selection")
            app.buttons["−10s"].click();ready(app)
            for phase in [2,3,1] {
                app.menuButtons["qualifyingPhaseSelector"].click();app.menuItems["Q\(phase)"].click();ready(app)
                XCTAssertTrue(text(app.staticTexts["sessionStatus"]).contains("Q\(phase)"))
                app.buttons["+10s"].click();ready(app)
                _=try evidence(app,"phase-\(key)-q\(phase)-opening")
            }
            app.terminate()
        }
    }
    @MainActor func testDeletedLapsAtSourceTime()throws {
        for (key,before,name) in [(11365,"2026-09-12T14:04:56Z","1:35.149"),(11249,"2026-03-28T06:51:07Z","1:31.537"),(11349,"2026-08-22T14:11:17Z","1:14.225")] {
            let app=launch(key,before,width:1200)
            let a=try evidence(app,"deletion-\(key)-before")
            app.buttons["+10s"].click();ready(app)
            XCTAssertTrue(app.debugDescription.contains(name))
            _=try evidence(app,"deletion-\(key)-after")
            app.buttons["−10s"].click();ready(app)
            XCTAssertEqual(a,try evidence(app,"deletion-\(key)-rewind"))
            app.buttons["+10s"].click();ready(app)
            XCTAssertTrue(app.debugDescription.contains(name))
            app.terminate()
        }
    }
    @MainActor func testSessionSwitches()throws {
        let app=launch(11365,"2026-09-12T14:13:05Z",width:1200)
        for key in [11361,11365,11363,11365,11363] {
            app.buttons["sessionsButton"].click()
            let search=app.textFields["sessionSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:10));search.click();search.typeText(String(key))
            let button=app.buttons["session-\(key)"]
            XCTAssertTrue(button.waitForExistence(timeout:30));button.click()
            expectation(for:NSPredicate{_,_ in !app.buttons["session-\(key)"].exists && app.buttons["playPause"].isEnabled},evaluatedWith:app);waitForExpectations(timeout:180)
            XCTAssertEqual(app.descendants(matching:.any)["qualifyingLeaderboard"].firstMatch.exists,key==11365)
            if key==11365 {XCTAssertTrue(app.menuButtons["qualifyingPin-0"].exists)}
            _=try evidence(app,"switch-to-\(key)")
        }
        app.terminate()
    }

    @MainActor func testSectorPlaybackSpeedsAndManualScrub()throws {
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        func date(_ s:String)->Date {formatter.date(from:s) ?? ISO8601DateFormatter().date(from:s)!}
        for key in [11365,11249,11349] {
            let c=try cases().first{$0.key==key && $0.phase==1}!
            let initial=date(c.s1).addingTimeInterval(-2)
            let app=launch(key,formatter.string(from:initial),width:1200)
            app.buttons["qualifyingDriver-\(c.driver)"].click()
            func sector(_ n:Int)->String {text(app.descendants(matching:.any)["qualifyingSector-\(c.driver)-\(n)"].firstMatch)}
            XCTAssertTrue(sector(1).contains("…"))
            let before=try evidence(app,"sectors-\(key)-before-s1")
            app.popUpButtons["replaySpeed"].click();app.menuItems["1×"].click()
            app.buttons["playPause"].click();Thread.sleep(forTimeInterval:3.2);app.buttons["playPause"].click()
            XCTAssertTrue(sector(1).contains(String(format:"%.3f",c.sectors[0])))
            _=try evidence(app,"sectors-\(key)-s1-1x")
            app.buttons["−10s"].click();ready(app);XCTAssertTrue(sector(1).contains("…"))
            app.buttons["+10s"].click();ready(app);XCTAssertTrue(sector(1).contains(String(format:"%.3f",c.sectors[0])))
            app.popUpButtons["replaySpeed"].click();app.menuItems["2×"].click()
            app.buttons["playPause"].click();Thread.sleep(forTimeInterval:c.sectors[1]/2);app.buttons["playPause"].click()
            XCTAssertTrue(sector(2).contains(String(format:"%.3f",c.sectors[1])))
            _=try evidence(app,"sectors-\(key)-s2-2x")
            app.buttons["−10s"].click();ready(app);XCTAssertTrue(sector(2).contains("…"))
            app.buttons["+10s"].click();ready(app);XCTAssertTrue(sector(2).contains(String(format:"%.3f",c.sectors[1])))
            app.popUpButtons["replaySpeed"].click();app.menuItems["5×"].click()
            app.buttons["playPause"].click()
            expectation(for:NSPredicate{_,_ in sector(3).contains(String(format:"%.3f",c.sectors[2]))},evaluatedWith:app);waitForExpectations(timeout:20)
            app.buttons["playPause"].click()
            _=try evidence(app,"sectors-\(key)-complete-5x")
            let slider=app.sliders.firstMatch
            slider.coordinate(withNormalizedOffset:CGVector(dx:0.06,dy:0.5)).click();ready(app)
            _=try evidence(app,"sectors-\(key)-manual-scrub")
            XCTAssertTrue(app.descendants(matching:.any)["qualifyingDashboard"].firstMatch.exists)
            XCTAssertFalse(before.isEmpty)
            app.terminate()
        }
    }

}
