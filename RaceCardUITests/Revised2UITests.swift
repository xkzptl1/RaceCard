import XCTest

final class Revised2UITests:XCTestCase {
    @MainActor func launch(_ args:[String])->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=args+["-language","ja","-mapLayer.cars","YES","-mapLayer.referenceMap","NO"];app.launch();app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout:5) {app.typeKey("n",modifierFlags:.command)}
        XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout:20));return app
    }
    @MainActor func shot(_ app:XCUIApplication,_ name:String) {let attachment=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)}
    @MainActor func testDedicatedAlertGeometryAndColorInBothThemes() {
        for theme in ["Light","Dark"] {
            let empty=launch(["--smoke","--mock-time","150","-theme",theme])
            XCTAssertTrue(empty.buttons["driver-4"].waitForExistence(timeout:20))
            let top=empty.descendants(matching:.any)["mapContent"].frame.minY;empty.terminate()
            for time in ["60","165","207"] {
                let app=launch(["--smoke","--mock-time",time,"-theme",theme])
                let alert=app.descendants(matching:.any)["mapAlertArea"],map=app.descendants(matching:.any)["mapContent"]
                XCTAssertTrue(alert.waitForExistence(timeout:20))
                XCTAssertLessThanOrEqual(alert.frame.maxY,map.frame.minY)
                XCTAssertGreaterThan(map.frame.minY,top+20)
                XCTAssertGreaterThan(alert.frame.width,map.frame.width*0.95)
                shot(app,"revised2 \(theme) reserved alert \(time)");app.terminate()
            }
        }
    }
    @MainActor func testTyreFeedGaugeAndOriginalBranding() {
        for theme in ["Light","Dark"] {
            let app=launch(["--smoke","--mock-time","122","-theme",theme])
            XCTAssertTrue(app.buttons["driver-4"].waitForExistence(timeout:20))
            shot(app,"revised2 \(theme) color logos and Japanese summary")
            app.buttons["driver-4"].click();XCTAssertTrue(app.descendants(matching:.any)["tyreUsageGauge"].waitForExistence(timeout:5))
            XCTAssertTrue(app.descendants(matching:.any)["focusedHeadshot"].exists)
            app.popUpButtons["replaySpeed"].click();app.menuItems["1×"].click();app.buttons["playPause"].click()
            let changed=app.staticTexts.matching(NSPredicate(format:"label CONTAINS 'ソフト → ハード' OR value CONTAINS 'ソフト → ハード'")).firstMatch
            XCTAssertTrue(changed.waitForExistence(timeout:8));app.buttons["playPause"].click()
            let compound=app.staticTexts["focusedCompound"]
            XCTAssertEqual(compound.value as? String ?? compound.label,"ハード")
            shot(app,"revised2 \(theme) synchronized tyre focus")
            app.buttons["closeFocus"].click();app.buttons["flipCard"].click()
            XCTAssertTrue(app.staticTexts["backTitle"].waitForExistence(timeout:5));shot(app,"revised2 \(theme) championship color logos");app.terminate()
        }
    }
    @MainActor func testRealHeadshotAndCachedFocus() {
        let app=launch(["--historical","11361","-theme","Light"])
        XCTAssertTrue(app.buttons["driver-63"].waitForExistence(timeout:120));app.buttons["driver-63"].click()
        let portrait=app.descendants(matching:.any)["focusedHeadshot"]
        XCTAssertTrue(portrait.waitForExistence(timeout:5))
        let loaded=NSPredicate {_,_ in (portrait.value as? String)=="写真表示中"}
        expectation(for:loaded,evaluatedWith:app);waitForExpectations(timeout:9)
        shot(app,"revised2 real Italian cached portrait and usage")
        app.buttons["closeFocus"].click();app.buttons["driver-63"].click()
        XCTAssertEqual(app.descendants(matching:.any)["focusedHeadshot"].value as? String,"写真表示中")
        app.buttons["flipCard"].click();XCTAssertTrue(app.staticTexts["backTitle"].waitForExistence(timeout:5));shot(app,"revised2 real championship portraits")
    }
    @MainActor func testOneShotPurpleAndPenaltyUseReservedArea() {
        for time in ["14","193"] {
            let app=launch(["--smoke","--mock-time",time,"-theme","Light"])
            XCTAssertTrue(app.buttons["driver-4"].waitForExistence(timeout:20))
            app.popUpButtons["replaySpeed"].click();app.menuItems["1×"].click();app.buttons["playPause"].click()
            let alert=app.descendants(matching:.any)["mapAlertArea"]
            XCTAssertTrue(alert.waitForExistence(timeout:8));app.buttons["playPause"].click()
            XCTAssertLessThanOrEqual(alert.frame.maxY,app.descendants(matching:.any)["mapContent"].frame.minY)
            shot(app,"revised2 one-shot reserved \(time)");app.terminate()
        }
    }
}
