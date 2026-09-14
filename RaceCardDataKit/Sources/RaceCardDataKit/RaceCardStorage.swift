import Foundation

/// Optional isolated data root for portable installs and clean-build validation.
/// The normal application continues to use standard per-user macOS directories.
public enum RaceCardStorage {
    private static var overrideRoot: URL? {
        guard let path=ProcessInfo.processInfo.environment["RACECARD_STORAGE_ROOT"],path.hasPrefix("/") else{return nil}
        return URL(fileURLWithPath:path,isDirectory:true)
    }
    public static var applicationSupport:URL {
        overrideRoot?.appendingPathComponent("ApplicationSupport") ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("RaceCard")
    }
    public static var caches:URL {
        overrideRoot?.appendingPathComponent("Caches") ?? FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("RaceCard")
    }
}
