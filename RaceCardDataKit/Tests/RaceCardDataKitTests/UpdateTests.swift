import XCTest
@testable import RaceCardDataKit
final class UpdateTests:XCTestCase {
    func testRejectDuplicateManifestEntries() {
        let file=MetadataManifest.File(path:"drivers.json",sha256:String(repeating:"a",count:64),bytes:2)
        XCTAssertThrowsError(try MetadataValidator.validate(MetadataManifest(schemaVersion:1,version:"v1",files:[file,file])))
    }
    func testRollbackUsesRetainedVersion() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root.appendingPathComponent("versions/one"),withIntermediateDirectories:true)
        try Data("one".utf8).write(to:root.appendingPathComponent("previous"))
        try Data("two".utf8).write(to:root.appendingPathComponent("active"))
        let updater=MetadataUpdater(root:root);try await updater.rollback()
        let active=await updater.activeRoot(fallback:root)
        XCTAssertEqual(active.lastPathComponent,"one")
    }
    func testMalformedDriverMetadataRejectedBeforeActivation() {
        let data=Data("[{\"id\":\"x\"}]".utf8)
        let file=MetadataManifest.File(path:"drivers.json",sha256:MetadataValidator.digest(data),bytes:data.count)
        XCTAssertThrowsError(try MetadataValidator.validate(data,file:file))
    }
}

private final class MetadataProtocol:URLProtocol {
    static var files:[String:Data]=[:]
    static var requests:[String]=[]
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        let path=request.url!.path
        Self.requests.append(path)
        let data=Self.files[path] ?? Data()
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:Self.files[path] == nil ? 404:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
extension UpdateTests {
    func testRemoteActivationChangedFilesCorruptionAndRollback() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[MetadataProtocol.self]
        let updater=MetadataUpdater(root:root,session:URLSession(configuration:configuration))
        let one=Data("{\"revision\":1}".utf8),two=Data("{\"revision\":2}".utf8),stable=Data("{}".utf8)
        func manifest(_ version:String,_ data:Data)throws->Data {
            try JSONEncoder().encode(MetadataManifest(schemaVersion:1,version:version,files:[.init(path:"content.json",sha256:MetadataValidator.digest(data),bytes:data.count),.init(path:"stable.json",sha256:MetadataValidator.digest(stable),bytes:stable.count)]))
        }
        MetadataProtocol.requests=[]
        MetadataProtocol.files=["/manifest.json":try manifest("one",one),"/content.json":one,"/stable.json":stable]
        let url=URL(string:"https://metadata.example.test/manifest.json")!
        let first=try await updater.update(manifestURL:url)
        XCTAssertEqual(try Data(contentsOf:first.appendingPathComponent("content.json")),one)
        MetadataProtocol.files["/manifest.json"]=try manifest("two",two);MetadataProtocol.files["/content.json"]=two
        let second=try await updater.update(manifestURL:url)
        XCTAssertEqual(try Data(contentsOf:second.appendingPathComponent("content.json")),two)
        XCTAssertEqual(MetadataProtocol.requests.filter{$0=="/stable.json"}.count,1)
        MetadataProtocol.files["/manifest.json"]=try manifest("broken",Data("{\"revision\":3}".utf8))
        do {_ = try await updater.update(manifestURL:url);XCTFail("Corrupt payload activated")} catch {}
        let active=await updater.activeRoot(fallback:root);XCTAssertEqual(active.path,second.path)
        try await updater.rollback();let restored=await updater.activeRoot(fallback:root);XCTAssertEqual(restored.path,first.path)
    }
}
