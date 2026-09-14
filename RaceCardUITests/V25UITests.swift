import XCTest
final class V25UITests:XCTestCase {
    @MainActor func launch(_ time:String,extra:[String]=[])->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--smoke","--mock-time",time,"-language","ja","-theme","Light"]+extra;app.launch();app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout:5){app.typeKey("n",modifierFlags:.command)}
        XCTAssertTrue(app.buttons["driver-10"].waitForExistence(timeout:25));return app
    }
    @MainActor func closeLayers(_ app:XCUIApplication) {
        app.buttons["closeMapLayers"].click()
        let gone=NSPredicate {_,_ in !app.buttons["closeMapLayers"].exists}
        expectation(for:gone,evaluatedWith:app);waitForExpectations(timeout:10)
    }
    @MainActor func checked(_ e:XCUIElement)->Bool {(e.value as? NSNumber)?.boolValue ?? ((e.value as? String)=="1")}
    @MainActor func shot(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    @MainActor func testFormationGridLightsAndPitStart() {
        for (time,text) in [("5","フォーメーションラップ"),("12","スターティンググリッドへ整列中"),("16","スタート確認待ち"),("22","消灯・レーススタート")] {
            let app=launch(time,extra:["--pit-start-fixture","-mapLayer.cars","YES"])
            if time == "5" || time == "12" {XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout:5))} else {XCTAssertFalse(app.staticTexts["消灯・レーススタート"].exists)}
            XCTAssertTrue(app.staticTexts["unrankedHeading"].exists)
            if time=="16" || time=="22" {XCTAssertTrue(app.descendants(matching:.any)["startLightHousing"].exists)}
            XCTAssertLessThan(app.buttons["driver-10"].frame.minY,app.buttons["driver-14"].frame.minY)
            if time=="22" {XCTAssertTrue(app.buttons["driver-14"].label.contains("順位取得中"))}
            shot(app,"v25 start phase "+time);app.terminate()
        }
    }
    @MainActor func testMapLayerPersistenceAndSafety() {
        var app=launch("60")
        app.buttons["mapLayer"].click();let sectors=app.checkBoxes["layer-sectors"];XCTAssertTrue(sectors.waitForExistence(timeout:4))
        if checked(sectors) {sectors.click()}
        closeLayers(app)
        XCTAssertTrue(app.descendants(matching:.any)["mapNotice"].exists);shot(app,"v25 full width persistent SC")
        app.terminate();app=launch("60");app.buttons["mapLayer"].click()
        XCTAssertTrue(app.checkBoxes["layer-sectors"].waitForExistence(timeout:4))
        XCTAssertFalse(checked(app.checkBoxes["layer-sectors"]))
        app.checkBoxes["layer-sectors"].click();closeLayers(app);app.terminate()
    }
    @MainActor func testThree2026LayerMaps() {
        for (event,key) in [("japan",11253),("monaco",11299),("italy",11361)] {
            let app=XCUIApplication();app.launchArguments=["--historical",String(key),"-language","ja","-theme","Light","-mapLayer.cars","YES"]
            app.launch();app.activate()
            if !app.windows.firstMatch.waitForExistence(timeout:5) {app.typeKey("n",modifierFlags:.command)}
            let replay=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@","リプレイ","リプレイ")).firstMatch
            XCTAssertTrue(replay.waitForExistence(timeout:240))
            app.buttons["mapLayer"].click();let cars=app.checkBoxes["layer-cars"]
            XCTAssertTrue(cars.waitForExistence(timeout:4));XCTAssertTrue(checked(cars))
            XCTAssertTrue(app.checkBoxes["layer-overtakeDetection"].exists)
            XCTAssertFalse(app.checkBoxes["layer-drsDetection"].exists)
            let corners=app.checkBoxes["layer-corners"];if corners.exists {corners.click();XCTAssertTrue(checked(cars));corners.click()}
            if event != "monaco" {XCTAssertTrue(app.checkBoxes["layer-straightMode"].exists)}
            closeLayers(app);shot(app,"v26 real canonical "+event);app.terminate()
        }
    }
    @MainActor func testFIASafetyAreaWithStaticSectorsHidden() {
        let app=launch("36",extra:["--reference-event","italy","--timing-sector-fixture"])
        app.buttons["mapLayer"].click();let cars=app.checkBoxes["layer-cars"];XCTAssertTrue(cars.waitForExistence(timeout:4));if checked(cars){cars.click()}
        let sectors=app.checkBoxes["layer-sectors"];if checked(sectors){sectors.click()};closeLayers(app)
        XCTAssertTrue(app.descendants(matching:.any)["racePhaseChip"].exists);shot(app,"v25 FIA safety sector with labels hidden")
        app.buttons["mapLayer"].click();app.checkBoxes["layer-cars"].click();app.checkBoxes["layer-sectors"].click();closeLayers(app)
    }
    @MainActor func testRealLegacyReplayLayers() {
        let app=XCUIApplication();app.launchArguments=["--historical","9165","-language","ja","-theme","Dark"];app.launch();app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout:5){app.typeKey("n",modifierFlags:.command)}
        XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout:120))
        XCTAssertTrue(app.buttons["driver-55"].waitForExistence(timeout:120))
        app.buttons["mapLayer"].click();XCTAssertTrue(app.checkBoxes["layer-drsDetection"].waitForExistence(timeout:5));XCTAssertFalse(app.checkBoxes["layer-overtakeDetection"].exists)
        let cars=app.checkBoxes["layer-cars"];if checked(cars) {cars.click()};closeLayers(app);shot(app,"v25 legacy FIA Singapore DRS")
        app.buttons["mapLayer"].click();app.checkBoxes["layer-cars"].click();closeLayers(app)
        app.buttons["playPause"].click();XCTAssertEqual(app.buttons["playPause"].label,"一時停止");shot(app,"v25 real historical replay")
    }
}
