import Foundation

public struct SourceEvidence:Codable,Equatable,Sendable {
    public var url:String;public var publisher:String;public var verifiedAt:String;public var confidence:String
    public init(url:String,publisher:String,verifiedAt:String,confidence:String="official_verified") {self.url=url;self.publisher=publisher;self.verifiedAt=verifiedAt;self.confidence=confidence}
}
public struct SourcedValue:Codable,Equatable,Sendable {
    public var value:String;public var sources:[SourceEvidence]
    public init(_ value:String,sources:[SourceEvidence]) {self.value=value;self.sources=sources}
}
public struct TemporalAssignment:Codable,Equatable,Identifiable,Sendable {
    public var id:String;public var personID:String;public var teamID:String;public var role:String
    public var validFrom:String;public var validTo:String?;public var sessionKey:Int?;public var meetingKey:Int?;public var sources:[SourceEvidence]
    public init(id:String,personID:String,teamID:String,role:String,validFrom:String,validTo:String?=nil,sessionKey:Int?=nil,meetingKey:Int?=nil,sources:[SourceEvidence]) {self.id=id;self.personID=personID;self.teamID=teamID;self.role=role;self.validFrom=validFrom;self.validTo=validTo;self.sessionKey=sessionKey;self.meetingKey=meetingKey;self.sources=sources}
    public func contains(_ date:String)->Bool {validFrom<=date && (validTo == nil || date < validTo!)}
}
public struct ChampionshipSeason:Codable,Equatable,Sendable {
    public var season:Int;public var position:Int?;public var points:Double?;public var titleNumber:Int?;public var clinchingEvent:String?;public var clinchingDate:String?;public var sources:[SourceEvidence]
}
public struct DriverMetadata:Codable,Identifiable,Sendable {
    public var id:String;public var fullName:String;public var acronym:String;public var numbers:[Int];public var numberSeasons:[String:[Int]]?;public var nationality:String?
    public var headshotURL:String?;public var facts:[String:SourcedValue];public var history:[TemporalAssignment];public var championships:[ChampionshipSeason];public var sources:[SourceEvidence]
}
public struct TeamMetadata:Codable,Identifiable,Sendable {
    public var id:String;public var name:String;public var aliases:[String];public var logoAsset:String?;public var logoPath:String?;public var logoSeason:Int?
    public var facts:[String:SourcedValue];public var history:[TemporalAssignment];public var staff:[TemporalAssignment];public var championships:[ChampionshipSeason];public var driverChampionships:[ChampionshipSeason]?;public var sources:[SourceEvidence]
}
public struct DriverSnapshot:Codable,Equatable,Sendable {
    public var identityID:String;public var season:Int;public var sessionKey:Int;public var meetingKey:Int;public var date:String;public var number:Int
    public var fullName:String;public var acronym:String;public var team:String;public var teamColor:String;public var headshotURL:String?;public var nationality:String?;public var sourceURL:String
    public init(identityID:String,season:Int,sessionKey:Int,meetingKey:Int,date:String,number:Int,fullName:String,acronym:String,team:String,teamColor:String,headshotURL:String?,nationality:String?=nil,sourceURL:String) {self.identityID=identityID;self.season=season;self.sessionKey=sessionKey;self.meetingKey=meetingKey;self.date=date;self.number=number;self.fullName=fullName;self.acronym=acronym;self.team=team;self.teamColor=teamColor;self.headshotURL=headshotURL;self.nationality=nationality;self.sourceURL=sourceURL}
}
public struct ResolvedDriver:Identifiable,Sendable {
    public var id:String;public var number:Int;public var fullName:String;public var acronym:String;public var team:String?;public var color:String;public var headshotURLs:[String];public var nationality:String?;public var diagnostic:String?;public var metadata:DriverMetadata?
}
public struct DriverRegistry:Sendable {
    public var records:[DriverSnapshot];public var metadata:[DriverMetadata]
    public init(records:[DriverSnapshot]=[],metadata:[DriverMetadata]=[]) {self.records=records;self.metadata=metadata}
    public static func stableID(_ name:String)->String {name.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX")).split(whereSeparator:{!$0.isLetter && !$0.isNumber}).joined(separator:"-")}
    public mutating func merge(_ incoming:[DriverSnapshot]) {
        for record in incoming where !record.fullName.isEmpty {
            records.removeAll{$0.sessionKey==record.sessionKey && $0.identityID==record.identityID};records.append(record)
        }
    }
    /// Consecutive observed affiliations, preserving session evidence rather than
    /// inventing contract dates between observations.
    public func observedHistory(identity:String)->[TemporalAssignment] {
        let appearances=records.filter{$0.identityID==identity && !$0.sourceURL.hasPrefix("mock:")}.sorted{$0.date<$1.date}
        var result:[TemporalAssignment]=[]
        var previousTeam:String?
        var previousSeason:Int?
        for record in appearances {
            guard record.team != previousTeam || record.season != previousSeason else {continue}
            result.append(TemporalAssignment(id:"observed-\(identity)-\(record.sessionKey)",personID:record.fullName,teamID:record.team,role:"Session entry",validFrom:record.date,sessionKey:record.sessionKey,meetingKey:record.meetingKey,sources:[SourceEvidence(url:record.sourceURL,publisher:"OpenF1",verifiedAt:String(record.date.prefix(10)),confidence:"provider_verified")]))
            previousTeam=record.team;previousSeason=record.season
        }
        return result
    }
    public func resolve(number:Int,season:Int,session:Int,meeting:Int,date:String)->ResolvedDriver {
        let candidates=records.filter{$0.number==number && $0.season==season && (!$0.sourceURL.hasPrefix("mock:") || $0.sessionKey==session)}.sorted {
            func priority(_ r:DriverSnapshot)->Int {r.sessionKey==session ? 0:r.meetingKey==meeting ? 1:2}
            return priority($0)==priority($1) ? $0.date>$1.date : priority($0)<priority($1)
        }
        let record=candidates.first
        let exact=record.flatMap{r in metadata.first{$0.id==r.identityID}}
        let byAcronym=record.map{r in metadata.filter{$0.acronym==r.acronym}} ?? []
        let meta=exact ?? (byAcronym.count == 1 ? byAcronym.first:byAcronym.first{$0.championships.contains{$0.season==season} || $0.numberSeasons?[String(season)]?.contains(number) == true}) ?? (record == nil ? metadata.first{$0.numberSeasons?[String(season)]?.contains(number) == true}:nil)
        let identity=record?.identityID ?? meta?.id ?? "unresolved-\(season)-\(number)"
        let team=record?.team.nonempty ?? meta?.history.last(where:{$0.contains(date) && $0.role=="Race Driver"})?.teamID
        var images=candidates.filter{$0.identityID==identity}.compactMap(\.headshotURL)
        images += records.filter{$0.identityID==identity}.sorted{$0.date>$1.date}.compactMap(\.headshotURL)
        if let url=meta?.headshotURL {images.append(url)}
        var seen=Set<String>();images=images.filter{seen.insert($0).inserted}
        return ResolvedDriver(id:identity,number:number,fullName:record?.fullName ?? meta?.fullName ?? "Unresolved driver · \(number)",acronym:record?.acronym ?? meta?.acronym ?? String(number),team:team,color:record?.teamColor ?? "888888",headshotURLs:images,nationality:record?.nationality ?? meta?.nationality,diagnostic:record==nil && meta==nil ? "No verified identity in session, meeting, season history or metadata":nil,metadata:meta)
    }
}
private extension String {var nonempty:String? {isEmpty ? nil:self}}
public struct TeamRegistry:Sendable {
    public var teams:[TeamMetadata]
    public init(teams:[TeamMetadata]=[]) {self.teams=teams}
    public func resolve(_ name:String)->TeamMetadata? {let key=DriverRegistry.stableID(name);return teams.first{([$0.id,$0.name]+$0.aliases).contains{DriverRegistry.stableID($0)==key}}}
}
public struct DriverMetadataRepository:Sendable {public let drivers:[DriverMetadata];public init(root:URL) throws {drivers=try JSONDecoder().decode([DriverMetadata].self,from:Data(contentsOf:root.appendingPathComponent("drivers.json")))}}
public struct TeamMetadataRepository:Sendable {public let teams:[TeamMetadata];public init(root:URL) throws {teams=try JSONDecoder().decode([TeamMetadata].self,from:Data(contentsOf:root.appendingPathComponent("teams.json")))}}
public struct AssetRegistry:Sendable {public let root:URL;public init(root:URL){self.root=root};public func file(_ path:String)->URL? {guard MetadataValidator.safePath(path) else{return nil};let url=root.appendingPathComponent(path);return FileManager.default.fileExists(atPath:url.path) ? url:nil}}

public actor OpenF1Sync {
    private let file:URL;private var records:[DriverSnapshot]
    public init(file:URL) {self.file=file;records=(try? JSONDecoder().decode([DriverSnapshot].self,from:Data(contentsOf:file))) ?? []}
    public func snapshots()->[DriverSnapshot] {records}
    public func removeSession(_ key:Int) throws {
        guard records.contains(where:{$0.sessionKey==key}) else{return}
        records.removeAll{$0.sessionKey==key}
        try JSONEncoder().encode(records).write(to:file,options:.atomic)
    }
    public func merge(_ incoming:[DriverSnapshot]) throws {
        var registry=DriverRegistry(records:records);registry.merge(incoming);records=registry.records
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(records).write(to:file,options:.atomic)
    }
}
