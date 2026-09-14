import XCTest
final class FinalPolishUITests:XCTestCase {
    @MainActor func resize(_ app:XCUIApplication) {let window=app.windows.firstMatch,frame=window.frame;let corner=window.coordinate(withNormalizedOffset:CGVector(dx:1,dy:1)).withOffset(CGVector(dx:-2,dy:-2));corner.press(forDuration:0.15,thenDragTo:corner.withOffset(CGVector(dx:700-frame.width,dy:932-frame.height)))}
    @MainActor func shot(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    @MainActor func ready(_ app:XCUIApplication) {expectation(for:NSPredicate{_,_ in app.buttons["playPause"].isEnabled && app.buttons["driver-1"].exists},evaluatedWith:app);waitForExpectations(timeout:120)}
    @MainActor func language(_ app:XCUIApplication,_ value:String) {app.buttons["gearshape"].click();let picker=app.popUpButtons["languagePicker"];XCTAssertTrue(picker.waitForExistence(timeout:5));picker.click();app.menuItems[value].click();app.buttons[value == "日本語" ? "完了":"Done"].click()}
    @MainActor func testRealArchiveHistoryTelemetryLanguageDensityAndSeeking() {
        let app=XCUIApplication();app.launchArguments=["--historical","11361","-language","en","-theme","Light","-mapDensity","Simple","-mapOverride.cars","YES"]
        app.launch();app.activate();if !app.windows.firstMatch.waitForExistence(timeout:5){app.typeKey("n",modifierFlags:.command)}
        ready(app);resize(app)
        XCTAssertTrue(app.descendants(matching:.any)["trackMap"].firstMatch.exists)
        app.buttons["+10s"].click();ready(app)
        app.buttons["driver-1"].click()
        XCTAssertTrue(app.descendants(matching:.any)["focusedTelemetry"].waitForExistence(timeout:10))
        XCTAssertTrue(app.descendants(matching:.any)["stint-1"].exists)
        app.buttons["closeFocus"].hover()
        let speed=app.descendants(matching:.any)["telemetry-Speed"].firstMatch
        expectation(for:NSPredicate{_,_ in speed.exists && (speed.label+String(describing:speed.value)).contains("km/h")},evaluatedWith:app);waitForExpectations(timeout:30)
        shot(app,"polish real Monza English focus telemetry")
        app.buttons["playPause"].click();Thread.sleep(forTimeInterval:2);app.buttons["playPause"].click()
        let frozen=String(describing:speed.value);Thread.sleep(forTimeInterval:1);XCTAssertEqual(String(describing:speed.value),frozen)
        app.buttons["−10s"].click();ready(app);XCTAssertTrue(app.descendants(matching:.any)["focusedTelemetry"].waitForExistence(timeout:10))
        app.buttons["+10s"].click();ready(app)
        app.buttons["driver-63"].click();XCTAssertTrue(app.descendants(matching:.any)["focusedTelemetry"].waitForExistence(timeout:10))
        language(app,"日本語");app.buttons["driver-1"].click()
        XCTAssertTrue(app.staticTexts["タイヤ履歴"].exists);shot(app,"polish real Monza Japanese focus")
        language(app,"English");app.buttons["driver-1"].click();XCTAssertTrue(app.staticTexts["Tyre history"].exists)
        app.buttons["closeFocus"].click();app.buttons["mapLayer"].click()
        app.radioButtons["Detailed"].click();XCTAssertEqual(app.checkBoxes["layer-cars"].value as? Int,1)
        app.buttons["closeMapLayers"].click();expectation(for:NSPredicate{_,_ in !app.buttons["closeMapLayers"].exists},evaluatedWith:app);waitForExpectations(timeout:5);shot(app,"polish Monza Detailed leader lines")
        app.buttons["mapLegend"].click();shot(app,"polish contextual map legend");app.typeKey(.escape,modifierFlags:[]);Thread.sleep(forTimeInterval:0.5)
        app.menuButtons["lapSelector"].click();app.menuItems["Lap 20"].click();ready(app)
        app.buttons["driver-1"].click();XCTAssertTrue(app.descendants(matching:.any)["stint-2"].waitForExistence(timeout:5));XCTAssertTrue(app.descendants(matching:.any)["stint-1"].exists)
        shot(app,"polish real Monza complete stint history after red flag")
        app.menuButtons["lapSelector"].click();app.menuItems["Lap 1"].click();ready(app)
        app.buttons["driver-1"].click();XCTAssertFalse(app.descendants(matching:.any)["stint-2"].exists)
        app.terminate()
    }
    @MainActor func testMultiStintHistoryBothThemes() {
        for theme in ["Light","Dark"] {
            let app=XCUIApplication();app.launchArguments=["--smoke","--mock-time","200","-language","en","-theme",theme];app.launch();app.activate();if !app.windows.firstMatch.waitForExistence(timeout:5){app.typeKey("n",modifierFlags:.command)}
            XCTAssertTrue(app.buttons["driver-4"].waitForExistence(timeout:20));resize(app);app.buttons["driver-4"].click()
            XCTAssertTrue(app.descendants(matching:.any)["stint-1"].exists);XCTAssertTrue(app.descendants(matching:.any)["stint-2"].exists)
            XCTAssertTrue(app.descendants(matching:.any)["focusedTelemetry"].waitForExistence(timeout:10))
            shot(app,"polish multi-stint "+theme);app.terminate()
        }
    }
    @MainActor func testRealNormalPitExitAndRedFlagSuspension() {
        for (cursor,driver,red) in [("2026-09-06T13:56:20Z",30,false),("2026-09-06T13:10:00Z",1,true)] {
            let app=XCUIApplication();app.launchArguments=["--historical","11361","--historical-cursor",cursor,"-language","en","-theme",red ? "Dark":"Light"]
            app.launch();app.activate();if !app.windows.firstMatch.waitForExistence(timeout:5){app.typeKey("n",modifierFlags:.command)};ready(app)
            if red {
                XCTAssertTrue(app.descendants(matching:.any)["mapNotice"].exists)
                XCTAssertTrue(app.debugDescription.contains("RED FLAG"))
                XCTAssertFalse(app.buttons["driver-1"].label.contains(" PIT "))
                shot(app,"polish real red flag lane duration context")
            } else {
                XCTAssertTrue(app.buttons["driver-30"].label.contains("PIT"))
                shot(app,"polish real normal pit entry")
                for _ in 0..<2 {app.buttons["+10s"].click();ready(app)}
                XCTAssertFalse(app.buttons["driver-30"].label.contains("PIT"))
                shot(app,"polish real normal pit exit cleared")
                for _ in 0..<2 {app.buttons["−10s"].click();ready(app)}
                XCTAssertTrue(app.buttons["driver-30"].label.contains("PIT"))
            }
            app.buttons["driver-\(driver)"].click();shot(app,red ? "polish suspended driver feed":"polish normal pit driver feed")
            app.terminate()
        }
    }

}
