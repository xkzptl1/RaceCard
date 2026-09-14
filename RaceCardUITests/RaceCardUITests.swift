import XCTest
final class RaceCardUITests: XCTestCase {
    @MainActor private func launch(_ app: XCUIApplication) {
        app.launch(); app.activate()
        if app.buttons["Don’t Reopen"].exists { app.buttons["Don’t Reopen"].click() }
        // macOS may remember a windowless state after a prior interrupted test run.
        if !app.windows.firstMatch.waitForExistence(timeout:5) { app.typeKey("n",modifierFlags:.command) }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout:10))
    }
    @MainActor func testMockPrimaryFlows() throws {
        let app = XCUIApplication(); app.launchArguments = ["--smoke","--mock-time","30","-language","en"]; launch(app)
        XCTAssertTrue(app.buttons["driver-4"].waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons["driver-7"].exists)
        app.buttons["playPause"].click()
        let map = app.descendants(matching:.any)["trackMap"]
        XCTAssertTrue(map.exists)
        XCTAssertGreaterThan(map.frame.width,app.buttons["driver-4"].frame.width*2.4)
        app.buttons["driver-4"].click(); app.buttons["inspectorButton"].click()
        XCTAssertTrue(app.buttons["closeInspector"].waitForExistence(timeout:5)); app.buttons["closeInspector"].click(); Thread.sleep(forTimeInterval:0.5)
        XCTAssertTrue(app.buttons["playPause"].exists)
        let screenshot = XCTAttachment(screenshot:app.windows.firstMatch.screenshot()); screenshot.name = "RaceCard compact mock"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["gearshape"].click(); XCTAssertTrue(app.staticTexts["RaceCard Settings"].waitForExistence(timeout:5)); app.buttons["Done"].click(); Thread.sleep(forTimeInterval:0.5)
    }
    @MainActor func testRealHistoricalWindowAndInspector() throws {
        let app = XCUIApplication(); app.launchArguments = ["--historical","9165","--results","-language","en"]; launch(app)
        let finished = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@","FINISHED","FINISHED")).firstMatch
        XCTAssertTrue(finished.waitForExistence(timeout:180))
        XCTAssertTrue(app.buttons["driver-55"].waitForExistence(timeout:15))
        app.buttons["driver-55"].click(); app.buttons["inspectorButton"].click()
        XCTAssertTrue(app.buttons["closeInspector"].waitForExistence(timeout:10))
        let inspector = XCTAttachment(screenshot:app.windows.firstMatch.screenshot()); inspector.name = "Real historical driver inspector"; inspector.lifetime = .keepAlways; add(inspector)
        app.buttons["closeInspector"].click(); Thread.sleep(forTimeInterval:0.5)
        let screenshot = XCTAttachment(screenshot:app.windows.firstMatch.screenshot()); screenshot.name = "Singapore 2023 historical race"; screenshot.lifetime = .keepAlways; add(screenshot)
        let playback = app.buttons["playPause"]
        XCTAssertTrue(playback.exists)
        XCTAssertEqual(playback.label,"Play")
        playback.click()
        let replay = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@","REPLAY","REPLAY")).firstMatch
        XCTAssertTrue(replay.waitForExistence(timeout:90))
        XCTAssertTrue(playback.waitForExistence(timeout:10))
        XCTAssertEqual(playback.label,"Pause")
        playback.click()
        XCTAssertEqual(playback.label,"Play")
        XCTAssertTrue(app.sliders["Replay time"].exists)

    }
    @MainActor func testJapaneseLanguageSwitch() throws {
        let app = XCUIApplication(); app.launchArguments = ["--smoke","--mock-time","30","-language","en"]; launch(app)
        XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout:15))
        if app.buttons["playPause"].label == "Pause" { app.buttons["playPause"].click() }
        app.buttons["gearshape"].click()
        app.popUpButtons["languagePicker"].click(); app.menuItems["日本語"].click()
        XCTAssertTrue(app.buttons["完了"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.windows.firstMatch.screenshot()); shot.name = "Japanese settings"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["完了"].click(); Thread.sleep(forTimeInterval:0.5)
        XCTAssertEqual(app.buttons["playPause"].label,"再生")
        XCTAssertTrue(app.buttons["sessionsButton"].exists)
        let window = XCTAttachment(screenshot:app.windows.firstMatch.screenshot()); window.name = "Japanese race card"; window.lifetime = .keepAlways; add(window)
        app.buttons["gearshape"].click()
        app.popUpButtons["languagePicker"].click(); app.menuItems["English"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout:5)); app.buttons["Done"].click(); Thread.sleep(forTimeInterval:0.5)
        XCTAssertEqual(app.buttons["playPause"].label,"Play")
    }
    @MainActor func testRealReplayControls() throws {
        let app = XCUIApplication(); app.launchArguments = ["--historical","9165","-language","en"]; launch(app)
        let replay = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@","REPLAY","REPLAY")).firstMatch
        XCTAssertTrue(replay.waitForExistence(timeout:180))
        XCTAssertTrue(app.buttons["driver-55"].waitForExistence(timeout:30))
        XCTAssertTrue(app.buttons["playPause"].exists)
        XCTAssertTrue(app.menuButtons["Lap 1"].exists)
        XCTAssertEqual(app.buttons["playPause"].label,"Play")
        app.buttons["playPause"].click()
        app.popUpButtons["replaySpeed"].click(); XCTAssertTrue(app.menuItems["5×"].waitForExistence(timeout:5)); app.menuItems["5×"].click()
        app.buttons["+10s"].click()
        XCTAssertTrue(replay.waitForExistence(timeout:90))
        XCTAssertTrue(app.buttons["driver-55"].waitForExistence(timeout:15))
        let screenshot = XCTAttachment(screenshot:app.windows.firstMatch.screenshot()); screenshot.name = "Singapore historical replay"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
