import Foundation
import CryptoKit
import ImageIO

public actor DriverImageRepository {
    public static let shared = DriverImageRepository()
    public typealias Fetch = @Sendable (URL) async throws -> Data
    private let root: URL
    private let fetch: Fetch
    private var memory: [String:Data] = [:]
    private var requests: [String:Task<Data?,Never>] = [:]
    private var failures: [String:Date] = [:]
    public init(root:URL? = nil,fetch:Fetch? = nil) {
        self.root=root ?? RaceCardStorage.caches.appendingPathComponent("Drivers")
        self.fetch=fetch ?? { url in
            let (data,response)=try await URLSession.shared.data(from:url)
            guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode),data.count<=8_000_000 else {throw URLError(.badServerResponse)}
            return data
        }
    }
    public func cachedImageData(season:Int,identity:String)->Data? {
        let key=SHA256.hash(data:Data(identity.utf8)).map{String(format:"%02x",$0)}.joined()
        for relative in ["identities/\(season)/\(key).png","identities/latest/\(key).png"] {
            if let data=try? Data(contentsOf:root.appendingPathComponent(relative)),Self.valid(data) {return data}
        }
        return nil
    }
    public func imageData(urls:[String],season:Int,identity:String) async -> Data? {
        let key=SHA256.hash(data:Data(identity.utf8)).map{String(format:"%02x",$0)}.joined()
        let seasonFile=root.appendingPathComponent("identities/\(season)/\(key).png")
        let priorFile=root.appendingPathComponent("identities/latest/\(key).png")
        var best=(try? Data(contentsOf:seasonFile)).flatMap { Self.valid($0) ? $0:nil }
        var bestURL:String?
        for url in urls {
            // Ask the same official asset for its original rendition, then try the supplied URL.
            let candidates=url.contains("media.formula1.com/") && url.contains(".transform/")
                ? [String(url.components(separatedBy:".transform/")[0]),url] : [url]
            for candidate in candidates {
                if let data=await imageData(url:candidate,season:season),Self.pixels(data)>Self.pixels(best) {
                    best=data;bestURL=candidate
                }
            }
        }
        if let best {
            for file in [seasonFile,priorFile] {
                let previous=try? Data(contentsOf:file)
                guard Self.pixels(best)>=Self.pixels(previous) else {continue}
                try? FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
                try? best.write(to:file,options:.atomic)
                if let bestURL,let source=CGImageSourceCreateWithData(best as CFData,nil),let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any] {
                    let metadata:[String:Any] = ["driverID":identity,"season":season,"sourceURL":bestURL,"pixelWidth":props[kCGImagePropertyPixelWidth as String] ?? 0,"pixelHeight":props[kCGImagePropertyPixelHeight as String] ?? 0,"fetchedAt":ISO8601DateFormatter().string(from:Date()),"revision":2]
                    if let encoded=try? JSONSerialization.data(withJSONObject:metadata,options:.sortedKeys) {try? encoded.write(to:file.appendingPathExtension("json"),options:.atomic)}
                }
            }
            return best
        }
        return (try? Data(contentsOf:priorFile)).flatMap {Self.valid($0) ? $0:nil}
    }
    nonisolated private static func pixels(_ data:Data?)->Int {
        guard let data,let source=CGImageSourceCreateWithData(data as CFData,nil),let p=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any] else{return 0}
        // Compare useful portrait resolution, not the extra pixels in a full-body image.
        let side=min(p[kCGImagePropertyPixelWidth as String] as? Int ?? 0,p[kCGImagePropertyPixelHeight as String] as? Int ?? 0)
        return side*side
    }
    public func imageData(url raw:String?,season:Int) async -> Data? {
        guard let raw,let url=URL(string:raw),url.scheme=="https",url.host != nil else{return nil}
        let hash=SHA256.hash(data:Data(raw.utf8)).map{String(format:"%02x",$0)}.joined()
        let key="original-v2/\(season)/\(hash)"
        if let data=memory[key] {return data}
        if let task=requests[key] {return await task.value}
        if let date=failures[key],Date().timeIntervalSince(date)<60 {return nil}
        let file=root.appendingPathComponent(key).appendingPathExtension("png"),fetch=self.fetch
        let task=Task.detached(priority:.utility) { () -> Data? in
            if let cached=try? Data(contentsOf:file),Self.valid(cached) {return cached}
            guard let data=try? await fetch(url),data.count<=8_000_000,Self.valid(data) else{return nil}
            let result=data // Preserve genuine source pixels; presentation downsamples.
            try? FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try? result.write(to:file,options:.atomic)
            return result
        }
        requests[key]=task
        let result=await task.value;requests[key]=nil
        if let result {memory[key]=result} else {failures[key]=Date()}
        return result
    }
    nonisolated private static func valid(_ data:Data)->Bool {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil) else{return false}
        return CGImageSourceCreateImageAtIndex(source,0,nil) != nil
    }
}
