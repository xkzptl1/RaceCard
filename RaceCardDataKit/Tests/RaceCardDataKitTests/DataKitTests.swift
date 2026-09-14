import XCTest
@testable import RaceCardDataKit
final class DataKitTests:XCTestCase {
    func testSportingNationalityLocalization() {
        XCTAssertEqual(Nationality.display("GBR",language:"en"),"United Kingdom")
        XCTAssertEqual(Nationality.display("NED",language:"en"),"Netherlands")
        XCTAssertEqual(Nationality.display("JPN",language:"ja"),"日本")
        XCTAssertNil(Nationality.display(nil,language:"en"))
    }
    func testCursorReconstructsStartAcrossSeek() {
        let date=Date(timeIntervalSince1970:100),lights=StartLightTimeline(anchor:Date(timeIntervalSince1970:100),source:.firstLapStart)
        XCTAssertEqual(lights.state(at:date.addingTimeInterval(-2))?.illuminated,5)
        XCTAssertEqual(lights.state(at:date)?.illuminated,0)
        XCTAssertNil(lights.state(at:date.addingTimeInterval(10)))
        XCTAssertEqual(lights.state(at:date.addingTimeInterval(-2))?.illuminated,5)
        XCTAssertNil(lights.state(at:date.addingTimeInterval(-10)))
    }
    func testInterpolationIsDeterministicAndRejectsGaps() {
        let date=Date(timeIntervalSince1970:100)
        let samples=[PositionSample(time:date,position:.init(x:0,y:0)),PositionSample(time:date.addingTimeInterval(1),position:.init(x:100,y:20))]
        XCTAssertEqual(PositionInterpolator.position(at:date.addingTimeInterval(0.5),samples:samples),.init(x:50,y:10))
        XCTAssertNil(PositionInterpolator.position(at:date.addingTimeInterval(-1),samples:samples))
        XCTAssertEqual(PositionInterpolator.position(at:date.addingTimeInterval(0.5),samples:samples,maximumDistance:20),.init(x:0,y:0))
    }
    func testRejectTraversalAndCorruptPayload() throws {
        for path in ["../active","/tmp/a","a/../b","a\\b","https://bad","a//b"] {XCTAssertFalse(MetadataValidator.safePath(path))}
        let data=Data("{}".utf8)
        let file=MetadataManifest.File(path:"valid.json",sha256:MetadataValidator.digest(data),bytes:data.count)
        XCTAssertNoThrow(try MetadataValidator.validate(data,file:file))
        XCTAssertThrowsError(try MetadataValidator.validate(Data("[]".utf8),file:file))
    }
    func testSessionIdentityWinsAndHistorySurvivesMerge() {
        func sample(_ session:Int,_ team:String)->DriverSnapshot {.init(identityID:"driver",season:2026,sessionKey:session,meetingKey:session,date:"2026-03-01",number:7,fullName:"Driver Name",acronym:"DRV",team:team,teamColor:"FFFFFF",headshotURL:nil,sourceURL:"https://api.openf1.org/v1/drivers")}
        var registry=DriverRegistry(records:[sample(1,"Old team")]);registry.merge([sample(2,"New team")])
        XCTAssertEqual(registry.records.count,2)
        XCTAssertEqual(registry.resolve(number:7,season:2026,session:1,meeting:1,date:"2026-03-01").team,"Old team")
        XCTAssertNotNil(registry.resolve(number:99,season:2026,session:1,meeting:1,date:"2026-03-01").diagnostic)
    }
    func testNumberReuseNeverSuppliesAnotherPersonsHeadshot() {
        let first=DriverSnapshot(identityID:"first",season:2026,sessionKey:1,meetingKey:1,date:"2026-03-01",number:7,fullName:"First Driver",acronym:"DRV",team:"Old",teamColor:"FFFFFF",headshotURL:"https://example.com/first.png",sourceURL:"https://api.openf1.org/v1/drivers")
        var second=first;second.identityID="second";second.sessionKey=2;second.meetingKey=2;second.date="2026-04-01";second.fullName="Second Driver";second.headshotURL="https://example.com/second.png"
        let registry=DriverRegistry(records:[first,second])
        XCTAssertEqual(registry.resolve(number:7,season:2026,session:1,meeting:1,date:first.date).headshotURLs,[first.headshotURL!])
        XCTAssertEqual(registry.resolve(number:7,season:2026,session:2,meeting:2,date:second.date).headshotURLs,[second.headshotURL!])
    }
    func testObservedTransferHistoryDoesNotInventContractDates() {
        let first=DriverSnapshot(identityID:"driver",season:2026,sessionKey:1,meetingKey:1,date:"2026-03-01",number:7,fullName:"Driver",acronym:"DRV",team:"Old",teamColor:"FFFFFF",headshotURL:nil,sourceURL:"https://api.openf1.org/v1/drivers")
        var next=first;next.sessionKey=2;next.date="2026-04-01";next.team="New"
        let history=DriverRegistry(records:[next,first]).observedHistory(identity:"driver")
        XCTAssertEqual(history.map(\.teamID),["Old","New"])
        XCTAssertTrue(history.allSatisfy{$0.validTo==nil && $0.sessionKey != nil})
    }

}

import CoreGraphics
import ImageIO
extension DataKitTests {
    func testCanonicalPortraitPreservesOriginalAndNeverDowngrades() async throws {
        func png(_ size:Int,_ height:Int? = nil)->Data {
            let h=height ?? size
            let context=CGContext(data:nil,width:size,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red:0.2,green:0.5,blue:0.7,alpha:1));context.fill(CGRect(x:0,y:0,width:size,height:h))
            let output=NSMutableData(),destination=CGImageDestinationCreateWithData(output,"public.png" as CFString,1,nil)!
            CGImageDestinationAddImage(destination,context.makeImage()!,nil);CGImageDestinationFinalize(destination);return output as Data
        }
        let small=png(93),large=png(840),body=png(720,2069)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let repository=DriverImageRepository(root:root,fetch:{url in url.lastPathComponent=="large.png" ? large:url.lastPathComponent=="body.png" ? body:small})
        let first=await repository.imageData(urls:["https://example.com/small.png","https://example.com/large.png"],season:2026,identity:"george-russell")
        XCTAssertEqual(first,large)
        let later=await repository.imageData(urls:["https://example.com/small.png"],season:2026,identity:"george-russell")
        XCTAssertEqual(later,large)
        let portrait=await repository.imageData(urls:["https://example.com/body.png"],season:2026,identity:"george-russell")
        XCTAssertEqual(portrait,large,"Extra full-body pixels must not replace a sharper headshot")
        let cached=await repository.cachedImageData(season:2026,identity:"george-russell")
        XCTAssertEqual(cached,large)
        let missing=await repository.imageData(urls:[],season:2027,identity:"george-russell")
        XCTAssertEqual(missing,large)
    }
}
