import XCTest
@testable import RaceCard

final class PublicBuildTests:XCTestCase {
    func testMissingLiveCredentialsFailsBeforeAnyNetworkRequest() async {
        let manager=TokenManager(credentials:{nil})
        do {_ = try await manager.access();XCTFail("Missing credentials must not authenticate")}
        catch {guard case ProviderError.noCredentials = error else{return XCTFail("Expected noCredentials")}}
    }
    @MainActor func testMissingTeamAssetHasNeutralFallback() {
        let missing=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library=TeamBrandLibrary();library.configure(root:missing,registry:.init())
        XCTAssertNil(library.image(season:2026,team:"McLaren"))
        XCTAssertEqual(TeamAssetRegistry.resolve(season:2026,name:"McLaren").monogram,"MCL")
    }
    @MainActor func testOfflineDemoDoesNotNeedHistoricalCache() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let model=AppModel(cachePath:file);model.loadMock()
        XCTAssertEqual(model.store.mode,.mock)
        XCTAssertFalse(model.store.drivers.isEmpty)
        XCTAssertFalse(model.store.track.isEmpty)
        XCTAssertNil(model.error)
    }
}
