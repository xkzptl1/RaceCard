import XCTest
final class CalendarMapUITests:XCTestCase {
    @MainActor func testEveryAvailableCalendarCircuitInProductionRenderer() {
        let events=["australia","china","japan","miami","canada","monaco","barcelona-catalunya","austria","great-britain","belgium","hungary","netherlands","italy","spain","azerbaijan","singapore","united-states","mexico","brazil","las-vegas","qatar","united-arab-emirates"]
        for event in events {
            let app=XCUIApplication();app.launchArguments=["--inspect-calibration","/private/tmp/RaceCardCalibrationSamples/"+event+".json","-language","en","-theme","Light","-mapLayer.cars","YES","-mapLayer.corners","YES","-mapLayer.sectors","YES","-mapLayer.pit","YES","-mapLayer.startFinish","YES"]
            app.launch();app.activate()
            if !app.windows.firstMatch.waitForExistence(timeout:5) {app.typeKey("n",modifierFlags:.command)}
            let map=app.descendants(matching:.any)["trackMap"].firstMatch
            XCTAssertTrue(map.waitForExistence(timeout:20),event)
            XCTAssertTrue(app.debugDescription.contains("Cars: 1"),event)
            XCTAssertTrue(app.debugDescription.contains("Calibrated circuit map"),event)
            let shot=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());shot.name="v26 calendar "+event;shot.lifetime = .keepAlways;add(shot)
            app.terminate()
        }
    }
}
