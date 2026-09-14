import XCTest
final class V26UITests:XCTestCase {
    @MainActor func testProfilesReturnToChampionshipAndLayersKeepCars() {
        let app=XCUIApplication();app.launchArguments=["--smoke","--mock-time","120","-language","en","-theme","Light","-mapLayer.cars","YES"]
        app.launch();app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout:5) {app.typeKey("n",modifierFlags:.command)}
        XCTAssertTrue(app.buttons["flipCard"].waitForExistence(timeout:20));app.buttons["flipCard"].click()
        let row=app.descendants(matching:.any)["driverProfile-4"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:10));row.click()
        XCTAssertTrue(app.buttons["closeProfile"].waitForExistence(timeout:5))
        XCTAssertTrue(app.debugDescription.contains("United Kingdom"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "Nationality unavailable")).firstMatch.exists)
        let shot=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());shot.name="v26 driver profile";shot.lifetime = .keepAlways;add(shot)
        app.buttons["closeProfile"].click();XCTAssertTrue(row.waitForExistence(timeout:5))
        let team=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","teamProfile-")).firstMatch
        XCTAssertTrue(team.waitForExistence(timeout:5));team.click()
        XCTAssertTrue(app.buttons["closeProfile"].waitForExistence(timeout:5))
        let teamShot=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());teamShot.name="v26 team profile";teamShot.lifetime = .keepAlways;add(teamShot)
        app.buttons["closeProfile"].click()
        app.buttons["flipCard"].click();app.buttons["mapLayer"].click()
        let cars=app.checkBoxes["layer-cars"],sectors=app.checkBoxes["layer-sectors"]
        XCTAssertTrue(cars.waitForExistence(timeout:5));let before=String(describing:cars.value)
        sectors.click();XCTAssertEqual(String(describing:cars.value),before)
        XCTAssertFalse(app.checkBoxes["layer-referenceMap"].exists)
        app.buttons["closeMapLayers"].click();app.terminate()
    }
    @MainActor func testRealMonzaMapAndStartSeek() {
        let app=XCUIApplication();app.launchArguments=["--historical","11361","-language","en","-theme","Light","-mapLayer.cars","YES"]
        app.launch();app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout:5) {app.typeKey("n",modifierFlags:.command)}
        let replay=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@","REPLAY","REPLAY")).firstMatch
        XCTAssertTrue(replay.waitForExistence(timeout:180))
        XCTAssertTrue(app.menuButtons["Lap 1"].exists)
        XCTAssertEqual(app.buttons["playPause"].label,"Play")
        XCTAssertTrue(app.descendants(matching:.any)["trackMap"].firstMatch.exists)
        XCTAssertFalse(app.debugDescription.contains("Lights out · race start"))
        app.buttons["−10s"].click()
        expectation(for:NSPredicate {_,_ in app.buttons["playPause"].isEnabled && replay.exists},evaluatedWith:app)
        waitForExpectations(timeout:60)
        app.buttons["+10s"].click()
        expectation(for:NSPredicate {_,_ in app.buttons["playPause"].isEnabled && replay.exists},evaluatedWith:app)
        waitForExpectations(timeout:60)
        app.buttons["+10s"].click()
        expectation(for:NSPredicate {_,_ in app.buttons["playPause"].isEnabled && replay.exists},evaluatedWith:app)
        waitForExpectations(timeout:60)
        let screenshot=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());screenshot.name="v26 real Monza Lap 1 map";screenshot.lifetime = .keepAlways;add(screenshot)
        app.buttons["flipCard"].click()
        XCTAssertTrue(app.descendants(matching:.any)["driverChampionship"].firstMatch.waitForExistence(timeout:10))
        XCTAssertFalse(app.debugDescription.contains("Team unavailable"))
        app.terminate()
    }
    @MainActor func testFallbackLightsAtTwoReplaySpeeds() {
        for speed in ["2×","5×"] {
            let app=XCUIApplication();app.launchArguments=["--smoke","--pit-start-fixture","--mock-time","16","-language","en","-theme","Dark"]
            app.launch();app.activate()
            if !app.windows.firstMatch.waitForExistence(timeout:5) {app.typeKey("n",modifierFlags:.command)}
            let lights=app.descendants(matching:.any)["startLightHousing"].firstMatch
            XCTAssertTrue(lights.waitForExistence(timeout:10))
            XCTAssertTrue(lights.label.contains("5 / 5"))
            app.popUpButtons["replaySpeed"].click();app.menuItems[speed].click()
            let screenshot=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());screenshot.name="v26 fallback lights "+speed;screenshot.lifetime = .keepAlways;add(screenshot)
            app.buttons["playPause"].click()
            expectation(for:NSPredicate {_,_ in !lights.exists},evaluatedWith:app);waitForExpectations(timeout:12)
            XCTAssertFalse(app.debugDescription.contains("Lights out · race start"))
            app.terminate()
        }
    }

}
