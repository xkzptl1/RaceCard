import XCTest
final class V24UITests:XCTestCase {
    @MainActor func launch(time:String="120",theme:String="Light")->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--smoke","--mock-time",time,"-language","ja","-theme",theme];app.launch();app.activate()
        if app.buttons["Don’t Reopen"].exists {app.buttons["Don’t Reopen"].click()}
        if !app.windows.firstMatch.waitForExistence(timeout:5){app.typeKey("n",modifierFlags:.command)}
        XCTAssertTrue(app.buttons["driver-4"].waitForExistence(timeout:25));resize(app,700,932);return app
    }
    @MainActor func resize(_ app:XCUIApplication,_ width:CGFloat,_ height:CGFloat) {
        let window=app.windows.firstMatch;let frame=window.frame
        let corner=window.coordinate(withNormalizedOffset:CGVector(dx:1,dy:1)).withOffset(CGVector(dx:-2,dy:-2))
        corner.press(forDuration:0.15,thenDragTo:corner.withOffset(CGVector(dx:width-frame.width,dy:height-frame.height)))
    }
    @MainActor func shot(_ app:XCUIApplication,_ title:String){let a=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());a.name=title;a.lifetime = .keepAlways;add(a)}
    @MainActor func testJapaneseFocusThreeDriversAndDismissal() {
        let app=launch();let map=app.descendants(matching:.any)["trackMap"]
        XCTAssertEqual(app.buttons["playPause"].label,"再生")
        for id in [4,1,16] {
            app.buttons["driver-\(id)"].click()
            XCTAssertTrue(app.buttons["closeFocus"].waitForExistence(timeout:3))
            XCTAssertTrue(app.descendants(matching:.any)["focusedTyres"].exists)
            XCTAssertFalse(app.descendants(matching:.any)["tyresBand"].exists)
            XCTAssertFalse(app.descendants(matching:.any)["fastestSummary"].exists)
            XCTAssertTrue(app.buttons["driver-77"].isHittable)
            shot(app,"v24 Japanese focus \(id)")
        }
        map.click();XCTAssertTrue(app.descendants(matching:.any)["tyresBand"].waitForExistence(timeout:3))
        app.buttons["driver-4"].click();app.buttons["closeFocus"].click()
        XCTAssertTrue(app.descendants(matching:.any)["tyresBand"].waitForExistence(timeout:3))
        for (w,h) in [(CGFloat(600),CGFloat(792)),(1050,982),(1450,1082)] {
            resize(app,w,h);app.buttons["driver-1"].click();XCTAssertTrue(app.buttons["driver-77"].isHittable)
            XCTAssertGreaterThan(app.buttons["driver-77"].frame.maxY,map.frame.maxY+100)
            shot(app,"v24 persistent tower \(Int(w))");app.buttons["closeFocus"].click()
        }
    }
    @MainActor func testFocusHoverPausesThenTimesOut() {
        let app=launch();app.buttons["driver-4"].click()
        app.buttons["closeFocus"].hover();Thread.sleep(forTimeInterval:11)
        XCTAssertTrue(app.buttons["closeFocus"].exists)
        app.buttons["gearshape"].hover()
        let gone=NSPredicate{_,_ in !app.buttons["closeFocus"].exists}
        expectation(for:gone,evaluatedWith:app);waitForExpectations(timeout:13)
        XCTAssertTrue(app.descendants(matching:.any)["tyresBand"].exists)
    }
    @MainActor func testThreeOfficialCircuitsAndJapaneseDarkBack() {
        let app=launch(theme:"Dark");app.buttons["metadataLibrary"].click()
        let picker=app.popUpButtons["metadataEventPicker"];XCTAssertTrue(picker.waitForExistence(timeout:5))
        for (slug,title) in [("japan","日本GP"),("monaco","モナコGP"),("italy","イタリアGP"),("bahrain","バーレーンGP")] {
            picker.click();app.menuItems[title].click()
            XCTAssertTrue(app.descendants(matching:.any)["staticCircuit-\(slug)"].waitForExistence(timeout:5))
            shot(app,"v24 official metadata \(slug)")
        }
        app.buttons["完了"].click();app.buttons["flipCard"].click()
        XCTAssertTrue(app.staticTexts["backTitle"].waitForExistence(timeout:5));shot(app,"v24 Japanese dark championship")
    }
    @MainActor func testFactualStartTransitionWithoutSyntheticLights() {
        let app=launch(time:"0");XCTAssertTrue(app.descendants(matching:.any)["startLightHousing"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["消灯・レーススタート"].exists)
        shot(app,"v24 source-confirmed race start")
        app.buttons["playPause"].click()
        let gone=NSPredicate{_,_ in !app.descendants(matching:.any)["startLightHousing"].exists}
        expectation(for:gone,evaluatedWith:app);waitForExpectations(timeout:8)
    }
    @MainActor func testExplicitMockLightRecords() {
        let app=XCUIApplication();app.launchArguments=["--smoke","--mock-start-lights","--mock-time","3","-language","ja","-theme","Light"];app.launch();app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout:5){app.typeKey("n",modifierFlags:.command)}
        XCTAssertTrue(app.buttons["driver-4"].waitForExistence(timeout:25));resize(app,700,932)
        XCTAssertTrue(app.descendants(matching:.any)["startLightHousing"].exists)
        XCTAssertFalse(app.staticTexts["消灯・レーススタート"].exists)
        shot(app,"v24 explicit fixture light records")
    }

}
