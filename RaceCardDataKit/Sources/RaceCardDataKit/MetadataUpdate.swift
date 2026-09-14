import Foundation
import CryptoKit

public struct MetadataManifest: Codable, Sendable {
    public struct File: Codable, Sendable {
        public var path: String
        public var sha256: String
        public var bytes: Int
    }
    public var schemaVersion: Int
    public var version: String
    public var files: [File]
}
public enum MetadataValidationError: Error { case invalidManifest, invalidPath, invalidContent(String), integrity(String), transport }
public enum MetadataValidator {
    public static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.split(separator:"/",omittingEmptySubsequences:false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) && !path.contains(":")
    }
    public static func digest(_ data: Data) -> String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
    public static func validateDirectory(_ root:URL) throws {
        let trackRoot=root.appendingPathComponent("TrackMetadata")
        guard FileManager.default.fileExists(atPath:trackRoot.path) else{return}
        let repository=TrackMetadataRepository(root:trackRoot)
        guard let calendar=repository.calendar,!calendar.events.isEmpty,Set(calendar.events.map(\.eventKey)).count==calendar.events.count else {throw MetadataValidationError.invalidContent("TrackMetadata/calendar.json")}
        let calibrations=trackRoot.appendingPathComponent("calibrations")
        for file in (try? FileManager.default.contentsOfDirectory(at:calibrations,includingPropertiesForKeys:nil)) ?? [] where file.pathExtension == "json" {
            let transform=try JSONDecoder().decode(CircuitCoordinateTransform.self,from:Data(contentsOf:file))
            guard transform.isValid else {throw MetadataValidationError.invalidContent(file.lastPathComponent)}
            if let path=transform.staticGeometryPath {
                guard safePath(path),try JSONDecoder().decode(MetadataGeometry.self,from:Data(contentsOf:trackRoot.appendingPathComponent(path))).valid else {throw MetadataValidationError.invalidContent(path)}
            }
        }
        for event in calendar.events {
            guard let metadata=repository.load(season:calendar.season,eventKey:event.eventKey),metadata.circuit.geometry?.value.valid != false else {throw MetadataValidationError.invalidContent(event.eventKey)}
            let sourceIDs=Set(metadata.provenance.sources.map(\.id))
            func check(_ value:Any)throws {
                if let dictionary=value as? [String:Any] {
                    if let ids=dictionary["sourceIds"] as? [String] {guard !ids.isEmpty,Set(ids).isSubset(of:sourceIDs) else {throw MetadataValidationError.invalidContent(event.eventKey)}}
                    for child in dictionary.values {try check(child)}
                } else if let array=value as? [Any] {for child in array {try check(child)}}
            }
            for name in ["circuit","tyres","pit","race_zones","energy","sources"] {
                let file=trackRoot.appendingPathComponent(String(calendar.season)).appendingPathComponent(event.eventKey).appendingPathComponent(name+".json")
                let data=try Data(contentsOf:file);try check(JSONSerialization.jsonObject(with:data))
            }
        }
    }
    public static func validate(_ manifest: MetadataManifest) throws {
        guard manifest.schemaVersion == 1, safePath(manifest.version), !manifest.version.contains("/"), !manifest.files.isEmpty, manifest.files.count <= 10000, Set(manifest.files.map(\.path)).count == manifest.files.count else { throw MetadataValidationError.invalidManifest }
        for file in manifest.files {
            guard safePath(file.path), file.bytes > 0, file.bytes <= 20_000_000, file.sha256.count == 64, file.sha256.allSatisfy({$0.isHexDigit}) else { throw MetadataValidationError.invalidManifest }
        }
    }
    public static func validate(_ data: Data, file: MetadataManifest.File) throws {
        guard data.count == file.bytes, digest(data) == file.sha256.lowercased() else { throw MetadataValidationError.integrity(file.path) }
        if file.path.hasSuffix(".json") {
            _ = try JSONSerialization.jsonObject(with:data)
            if file.path.contains("/calibrations/") {
                let transform=try JSONDecoder().decode(CircuitCoordinateTransform.self,from:data)
                guard transform.isValid,transform.validation.meanDistance<0.012,transform.validation.p95Distance<0.03,transform.validation.maxDistance<0.08 else {throw MetadataValidationError.invalidContent(file.path)}
            }
            if file.path.contains("/geometries/") {
                guard try JSONDecoder().decode(MetadataGeometry.self,from:data).valid else {throw MetadataValidationError.invalidContent(file.path)}
            }
            if file.path == "drivers.json" {
                let records = try JSONDecoder().decode([DriverMetadata].self,from:data)
                guard Set(records.map(\.id)).count == records.count, records.allSatisfy({ !$0.fullName.isEmpty && !$0.sources.isEmpty && $0.facts.values.allSatisfy{!$0.sources.isEmpty} }) else {throw MetadataValidationError.invalidContent(file.path)}
            }
            if file.path == "snapshots.json" {
                let records=try JSONDecoder().decode([DriverSnapshot].self,from:data)
                guard records.allSatisfy({!$0.identityID.isEmpty && !$0.fullName.isEmpty && URL(string:$0.sourceURL)?.scheme == "https"}) else {throw MetadataValidationError.invalidContent(file.path)}
            }
            if file.path == "teams.json" {
                let records = try JSONDecoder().decode([TeamMetadata].self,from:data)
                guard Set(records.map(\.id)).count == records.count, records.allSatisfy({ !$0.name.isEmpty && !$0.sources.isEmpty && $0.facts.values.allSatisfy{!$0.sources.isEmpty} }) else {throw MetadataValidationError.invalidContent(file.path)}
            }
        }
    }
}
/// A version is made visible only after every member passes validation. The pointer is
/// atomically replaced; the previous version is retained for explicit rollback.
public actor MetadataUpdater {
    public let root: URL
    private let session:URLSession
    private let requiredPaths:Set<String>
    public init(root: URL,session:URLSession = .shared,requiredPaths:Set<String>=[]) { self.root = root;self.session=session;self.requiredPaths=requiredPaths }
    public func activeRoot(fallback: URL) -> URL {
        guard let version = try? String(contentsOf:root.appendingPathComponent("active"),encoding:.utf8), MetadataValidator.safePath(version) else {return fallback}
        let folder = root.appendingPathComponent("versions").appendingPathComponent(version)
        return FileManager.default.fileExists(atPath:folder.path) ? folder : fallback
    }
    public func update(manifestURL: URL) async throws -> URL {
        guard manifestURL.scheme == "https" || (manifestURL.scheme == "http" && ["localhost","127.0.0.1"].contains(manifestURL.host ?? "")) else {throw MetadataValidationError.transport}
        let (data,response) = try await session.data(from:manifestURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000 else {throw MetadataValidationError.transport}
        let manifest = try JSONDecoder().decode(MetadataManifest.self,from:data)
        try MetadataValidator.validate(manifest)
        guard requiredPaths.isSubset(of:Set(manifest.files.map(\.path))) else {throw MetadataValidationError.invalidManifest}
        let fm = FileManager.default
        try fm.createDirectory(at:root.appendingPathComponent("versions"),withIntermediateDirectories:true)
        let stage = root.appendingPathComponent("stage-"+UUID().uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:true)
        defer {try? fm.removeItem(at:stage)}
        let current = activeRoot(fallback:root.appendingPathComponent("none"))
        for file in manifest.files {
            let old = current.appendingPathComponent(file.path)
            let body: Data
            if let cached = try? Data(contentsOf:old), (try? MetadataValidator.validate(cached,file:file)) != nil {body = cached}
            else {
                let url = manifestURL.deletingLastPathComponent().appendingPathComponent(file.path)
                let (download,reply) = try await session.data(from:url)
                guard (reply as? HTTPURLResponse)?.statusCode == 200, reply.url?.host == manifestURL.host else {throw MetadataValidationError.transport}
                body = download
            }
            try MetadataValidator.validate(body,file:file)
            let destination = stage.appendingPathComponent(file.path)
            try fm.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
            try body.write(to:destination)
        }
        try MetadataValidator.validateDirectory(stage)
        try data.write(to:stage.appendingPathComponent("manifest.json"))
        let final = root.appendingPathComponent("versions").appendingPathComponent(manifest.version)
        if fm.fileExists(atPath:final.path) {
            guard (try? Data(contentsOf:final.appendingPathComponent("manifest.json"))) == data else {throw MetadataValidationError.invalidManifest}
            if current.path == final.path {return final}
        } else {try fm.moveItem(at:stage,to:final)}
        if let prior = try? Data(contentsOf:root.appendingPathComponent("active")) {try prior.write(to:root.appendingPathComponent("previous"),options:.atomic)}
        try Data(manifest.version.utf8).write(to:root.appendingPathComponent("active"),options:.atomic)
        return final
    }
    public func rollback() throws {
        let previous = try Data(contentsOf:root.appendingPathComponent("previous"))
        guard let version = String(data:previous,encoding:.utf8), MetadataValidator.safePath(version), FileManager.default.fileExists(atPath:root.appendingPathComponent("versions").appendingPathComponent(version).path) else {throw MetadataValidationError.invalidManifest}
        try previous.write(to:root.appendingPathComponent("active"),options:.atomic)
    }
}
