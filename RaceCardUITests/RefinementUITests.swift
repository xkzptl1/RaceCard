import XCTest

final class RefinementUITests: XCTestCase {
    @MainActor func launch(_ args:[String])->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=args+["-language","en"];app.launch();app.activate()
        if app.buttons["Don’t Reopen"].exists { app.buttons["Don’t Reopen"].click() }
        if !app.windows.firstMatch.waitForExistence(timeout:5) { app.typeKey("n",modifierFlags:.command) }
        XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout:20));return app
    }
    @MainActor func resize(_ app:XCUIApplication,_ width:CGFloat,_ height:CGFloat) {
        let w=app.windows.firstMatch;let f=w.frame
        let corner=w.coordinate(withNormalizedOffset:CGVector(dx:1,dy:1)).withOffset(CGVector(dx:-2,dy:-2))
        corner.press(forDuration:0.15,thenDragTo:corner.withOffset(CGVector(dx:width-f.width,dy:height-f.height)))
    }
    @MainActor func shot(_ app:XCUIApplication,_ name:String) { let a=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
    @MainActor func testResponsiveFrontBackThemesAndBranding() {
        let app=launch(["--smoke","--mock-time","60","-theme","Light"])
        XCTAssertTrue(app.buttons["driver-77"].waitForExistence(timeout:20))
        XCTAssertFalse(app.staticTexts["backTitle"].exists)
        XCTAssertFalse(app.descendants(matching:.any)["driverChampionship"].exists)
        resize(app,600,852);shot(app,"v22 compact light front")
        XCTAssertTrue(app.buttons["driver-77"].isHittable)
        let map=app.descendants(matching:.any)["trackMap"];let compactWidth=map.frame.width
        resize(app,1050,982);shot(app,"v22 regular light front")
        XCTAssertGreaterThan(map.frame.width,compactWidth*1.4)
        app.buttons["flipCard"].click();XCTAssertTrue(app.staticTexts["backTitle"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["driverChampionship"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["constructorChampionship"].exists)
        XCTAssertFalse(app.buttons["driver-4"].exists)
        shot(app,"v22 regular championship back")
        app.buttons["flipCard"].click();XCTAssertTrue(app.buttons["driver-4"].waitForExistence(timeout:5));XCTAssertEqual(app.buttons["playPause"].label,"Play")
        app.buttons["gearshape"].click();XCTAssertTrue(app.popUpButtons["themePicker"].waitForExistence(timeout:5));app.popUpButtons["themePicker"].click();app.menuItems["Dark"].click();app.buttons["Done"].click()
        resize(app,600,852)
        app.sliders["Replay time"].adjust(toNormalizedSliderPosition:0.65)
        Thread.sleep(forTimeInterval:0.6)
        shot(app,"v22 compact dark factual status")
        resize(app,1450,1082);shot(app,"v22 wide dark front")
        XCTAssertGreaterThan(map.frame.width,compactWidth*2)
        app.buttons["flipCard"].click();XCTAssertTrue(app.staticTexts["backTitle"].waitForExistence(timeout:5));shot(app,"v22 wide dark championship back")
    }
    @MainActor func testMajorOverlayAndSpatialMovement() {
        let app=launch(["--smoke","--mock-time","10","-theme","Light"])
        XCTAssertTrue(app.buttons["driver-4"].waitForExistence(timeout:20))
        app.popUpButtons["replaySpeed"].click();app.menuItems["1×"].click()
        let before=app.buttons["driver-4"].frame.minY
        app.buttons["playPause"].click()
        let moved=NSPredicate { _,_ in app.buttons["driver-4"].frame.minY > before+8 }
        expectation(for:moved,evaluatedWith:app);waitForExpectations(timeout:8)
        shot(app,"v22 multi-car reorder")
        app.buttons["playPause"].click()
        // Jump close to SC deployment, then let the source event arrive naturally.
        let slider=app.sliders["Replay time"];slider.adjust(toNormalizedSliderPosition:0.175)
        app.buttons["playPause"].click()
        XCTAssertTrue(app.descendants(matching:.any)["mapNotice"].waitForExistence(timeout:10))
        shot(app,"v22 safety-car map banner")
        app.buttons["playPause"].click()
        XCTAssertTrue(app.descendants(matching:.any)["racePhaseChip"].exists)
        // v2.5 keeps the full-width persistent safety notice until factual state end.
        Thread.sleep(forTimeInterval:6)
        XCTAssertTrue(app.descendants(matching:.any)["mapNotice"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["racePhaseChip"].exists)
        shot(app,"v22 persistent SC badge")
        slider.adjust(toNormalizedSliderPosition:0.34)
        Thread.sleep(forTimeInterval:0.5)
        let singleBefore=app.buttons["driver-4"].frame.minY
        app.buttons["playPause"].click()
        let singleMoved=NSPredicate { _,_ in app.buttons["driver-4"].frame.minY > singleBefore+8 }
        expectation(for:singleMoved,evaluatedWith:app);waitForExpectations(timeout:8)
        shot(app,"v22 single-place reorder")
        app.buttons["playPause"].click()
    }
    @MainActor func testRealHistoricalChampionshipHeadshotsAndSectors() {
        let app=launch(["--historical","9165","--results","-theme","Light"])
        XCTAssertTrue(app.buttons["driver-55"].waitForExistence(timeout:180))
        let loaded=app.staticTexts.matching(NSPredicate(format:"label CONTAINS 'FINISHED' OR value CONTAINS 'FINISHED'")).firstMatch
        XCTAssertTrue(loaded.waitForExistence(timeout:180))
        resize(app,800,982);shot(app,"v22 Singapore real sectors")
        app.buttons["flipCard"].click();XCTAssertTrue(app.staticTexts["backTitle"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["driverChampionship"].exists)
        shot(app,"v22 Singapore official championship")
    }
}
