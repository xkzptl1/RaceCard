import Foundation
import Observation
import RaceCardDataKit

@MainActor @Observable final class IdentityLibrary {
    var registry:DriverRegistry
    var teams:TeamRegistry
    var diagnostic:String?
    var metadataRoot:URL
    var activeVersion:String {metadataRoot.lastPathComponent == "IdentityMetadata" ? "Bundled 2026.09.12":metadataRoot.lastPathComponent}
    private let folder:URL
    private let sync:OpenF1Sync
    private var task:Task<Void,Never>?
    init() {
        folder=RaceCardStorage.applicationSupport.appendingPathComponent("Metadata")
        let bundled=Bundle.main.resourceURL!.appendingPathComponent("IdentityMetadata")
        let version=(try? String(contentsOf:folder.appendingPathComponent("active"),encoding:.utf8)) ?? ""
        let cached=folder.appendingPathComponent("versions").appendingPathComponent(version)
        let root=MetadataValidator.safePath(version) && FileManager.default.fileExists(atPath:cached.path) ? cached:bundled
        metadataRoot=root
        registry=DriverRegistry(records:(try? JSONDecoder().decode([DriverSnapshot].self,from:Data(contentsOf:folder.appendingPathComponent("openf1.json")))) ?? [],metadata:(try? DriverMetadataRepository(root:root).drivers) ?? [])
        teams=TeamRegistry(teams:(try? TeamMetadataRepository(root:root).teams) ?? [])
        sync=OpenF1Sync(file:folder.appendingPathComponent("openf1.json"))
        registry.records.removeAll{$0.sessionKey == MockF1Provider.session.id}
        TeamBrandLibrary.shared.configure(root:root,registry:teams)
        registry.merge((try? JSONDecoder().decode([DriverSnapshot].self,from:Data(contentsOf:root.appendingPathComponent("snapshots.json")))) ?? [])
        DriverPortraitSources.records=registry.records

    }
    func importSnapshots(_ records:[DriverSnapshot]) async {registry.merge(records);try? await sync.merge(records)}
    func updateRemote() async {
        guard let raw=UserDefaults.standard.string(forKey:"metadataManifestURL"),let url=URL(string:raw),!raw.isEmpty else{return}
        do {
            let root=try await MetadataUpdater(root:folder,requiredPaths:["drivers.json","teams.json","snapshots.json","TrackMetadata/calendar.json"]).update(manifestURL:url)
            registry.metadata=try DriverMetadataRepository(root:root).drivers
            registry.merge((try? JSONDecoder().decode([DriverSnapshot].self,from:Data(contentsOf:root.appendingPathComponent("snapshots.json")))) ?? [])
        DriverPortraitSources.records=registry.records
            metadataRoot=root
            teams=TeamRegistry(teams:try TeamMetadataRepository(root:root).teams)
            TeamBrandLibrary.shared.configure(root:root,registry:teams)
            diagnostic=nil
        } catch {diagnostic="Metadata update failed; using last verified library: \(error.localizedDescription)"}
    }
    func rollback() async {
        let updater=MetadataUpdater(root:folder)
        do {
            try await updater.rollback()
            let root=await updater.activeRoot(fallback:metadataRoot)
            let drivers=try DriverMetadataRepository(root:root).drivers
            let restoredTeams=try TeamMetadataRepository(root:root).teams
            registry.metadata=drivers;teams=TeamRegistry(teams:restoredTeams);metadataRoot=root
            TeamBrandLibrary.shared.configure(root:root,registry:teams);diagnostic=nil
        } catch {diagnostic="No previous verified metadata version is available"}
    }
    func refresh(_ session:SessionState,drivers:[DriverState]) {
        let season=Calendar.current.component(.year,from:session.start)
        let local=drivers.map { d in DriverSnapshot(identityID:DriverRegistry.stableID(d.name),season:season,sessionKey:session.id,meetingKey:session.meeting,date:Dates.iso(session.start),number:d.id,fullName:d.name,acronym:d.acronym,team:d.team,teamColor:d.color,headshotURL:d.headshotURL,sourceURL:session.id == MockF1Provider.session.id ? "mock://drivers":"https://api.openf1.org/v1/drivers?session_key=\(session.id)") }
        registry.merge(local)
        DriverPortraitSources.records=registry.records
        task?.cancel()
        task=Task {
            try? await sync.removeSession(MockF1Provider.session.id)
            guard session.id != MockF1Provider.session.id else{return}
            try? await sync.merge(local)
            do {
                try await sync.synchronizeSeason(season,through:Dates.iso(Date()),excluding:session.id) { [weak self] records in
                    await MainActor.run {self?.registry.merge(records)}
                }
            } catch is CancellationError {} catch {diagnostic="Identity sync unavailable; cached verified identities remain available"}
        }
    }
    func resolve(_ number:Int,session:SessionState?)->ResolvedDriver {
        registry.resolve(number:number,season:Calendar.current.component(.year,from:session?.start ?? Date()),session:session?.id ?? 0,meeting:session?.meeting ?? 0,date:Dates.iso(session?.start ?? Date()))
    }
}
