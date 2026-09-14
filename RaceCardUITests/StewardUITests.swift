import XCTest
final class StewardUITests:XCTestCase {
    @MainActor func launch(_ cursor:String,language:String="en")->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--historical","11361","--historical-cursor",cursor,"-language",language,"-theme","Light","-mapDensity","Simple"]
        app.launch();app.activate();if !app.windows.firstMatch.waitForExistence(timeout:5){app.typeKey("n",modifierFlags:.command)}
        ready(app);return app
    }
    @MainActor func ready(_ app:XCUIApplication) {expectation(for:NSPredicate{_,_ in app.buttons["playPause"].exists && app.buttons["playPause"].isEnabled && app.buttons["driver-11"].exists},evaluatedWith:app);waitForExpectations(timeout:120)}
    @MainActor func shot(_ app:XCUIApplication,_ name:String) {Thread.sleep(forTimeInterval:0.4);let a=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    @MainActor func testRealPerezPenaltyAndIndependentInvestigation() {
        let app=launch("2026-09-06T14:21:59Z")
        XCTAssertTrue(app.buttons["driver-11"].label.contains("INV"));app.buttons["driver-11"].hover();shot(app,"steward Perez two factual investigations")
        app.buttons["driver-11"].click();app.buttons["stewardDetails"].click()
        XCTAssertGreaterThan(app.descendants(matching:.any)["stewardDetailContent"].frame.height,80);XCTAssertTrue(app.debugDescription.contains("escape-road"));XCTAssertTrue(app.debugDescription.contains("Practice start") || app.debugDescription.contains("practice start"))
        shot(app,"steward Perez English factual reasons");app.typeKey(.escape,modifierFlags:[])
        app.buttons["+10s"].click();ready(app)
        XCTAssertTrue(app.buttons["driver-11"].label.contains("+5s"));shot(app,"steward Perez penalty supersedes matching investigation")
        app.buttons["driver-11"].click();app.buttons["stewardDetails"].click();shot(app,"steward Perez penalty and separate earlier incident")
        XCTAssertTrue(app.debugDescription.contains("5-second time penalty"));app.typeKey(.escape,modifierFlags:[])
        app.buttons["−10s"].click();ready(app);XCTAssertTrue(app.buttons["driver-11"].label.contains("INV"));XCTAssertFalse(app.buttons["driver-11"].label.contains("+5s"))
        app.buttons["+10s"].click();ready(app);XCTAssertTrue(app.buttons["driver-11"].label.contains("+5s"))
        app.terminate()
    }
    @MainActor func testRealRussellNoFurtherActionAndJapaneseDetails() {
        let app=launch("2026-09-06T14:35:44Z",language:"ja")
        XCTAssertTrue(app.buttons["driver-63"].label.contains("INV") || app.buttons["driver-63"].label.contains("審議"))
        app.buttons["driver-63"].click();app.buttons["stewardDetails"].click()
        XCTAssertTrue(app.debugDescription.contains("黄旗規定違反"));shot(app,"steward Russell Japanese reason")
        app.typeKey(.escape,modifierFlags:[]);app.buttons["+10秒"].click();ready(app)
        XCTAssertFalse(app.buttons["driver-63"].label.contains("INV"));XCTAssertFalse(app.buttons["driver-63"].label.contains("審議"))
        app.buttons["driver-63"].click();XCTAssertFalse(app.buttons["stewardDetails"].exists)
        XCTAssertTrue(app.debugDescription.contains("処分なし"));shot(app,"steward Russell no further action clears investigation")
        app.buttons["−10秒"].click();ready(app)
        XCTAssertTrue(app.buttons["driver-63"].label.contains("INV") || app.buttons["driver-63"].label.contains("審議"))
        app.terminate()
    }
}
