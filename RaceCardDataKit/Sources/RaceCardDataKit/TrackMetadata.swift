import Foundation
public typealias TrackPoint = Coordinate

public struct Researched<Value: Codable>: Codable {
    public let value: Value
    public let sourceIds: [String]
    public let confidence: String
    public var isOfficial: Bool { confidence == "official_verified" }
}
public struct EventIdentity: Codable {
    public let meetingKey: Int; public let meetingName: String; public let circuitName: String; public let circuitKey: Int
    public let dateStart: String; public let dateEnd: String
}
public struct MetadataCalendar: Codable {
    public let season: Int; public let asOf: String; public let events: [CalendarEvent]
}
public struct CalendarEvent: Codable, Identifiable {
    public let eventKey: String; public let meetingKey: Int; public let meetingName: String; public let circuitName: String; public let circuitKey: Int
    public let dateStart: String; public let dateEnd: String
    public var id: String { eventKey }
}
public struct MetadataMarker: Codable { public let label: String; public let position: TrackPoint; public init(label:String,position:TrackPoint){self.label=label;self.position=position} }
public struct MetadataTurn: Codable { public let number: Int; public let label: String; public let position: TrackPoint?; public init(number:Int,label:String,position:TrackPoint?){self.number=number;self.label=label;self.position=position} }
public struct ZoneAnnotation: Codable { public let label: String; public let kind: String; public let position: TrackPoint; public init(label:String,kind:String,position:TrackPoint){self.label=label;self.kind=kind;self.position=position} }
public struct OperationalRing: Codable { public let kind:String;public let points:[TrackPoint] }
public struct TimingSectorArea: Codable {public let number:Int;public let rings:[[TrackPoint]]}
public struct MetadataGeometry: Codable {
    public init(coordinateSpace:String,roadRings:[[TrackPoint]],turns:[MetadataTurn]=[],sectorMarkers:[MetadataMarker]=[],zoneAnnotations:[ZoneAnnotation]=[],timingSectorAreas:[TimingSectorArea]?=nil,informationMarkers:[ZoneAnnotation]?=nil,operationalRings:[OperationalRing]?=nil,raceControlAreas:[TimingSectorArea]?=nil) {
        self.coordinateSpace=coordinateSpace;self.roadRings=roadRings;self.turns=turns;self.sectorMarkers=sectorMarkers;self.zoneAnnotations=zoneAnnotations;self.timingSectorAreas=timingSectorAreas;self.informationMarkers=informationMarkers;self.operationalRings=operationalRings;self.raceControlAreas=raceControlAreas
    }

    public let raceControlAreas:[TimingSectorArea]?
    public let timingSectorAreas:[TimingSectorArea]?
    public let informationMarkers:[ZoneAnnotation]?
    public let operationalRings:[OperationalRing]?
    public let coordinateSpace: String; public let roadRings: [[TrackPoint]]; public let turns: [MetadataTurn]
    public let sectorMarkers: [MetadataMarker]; public let zoneAnnotations: [ZoneAnnotation]
    public var valid: Bool {
        let points = (raceControlAreas ?? []).flatMap{$0.rings.flatMap{$0}} + (timingSectorAreas ?? []).flatMap{ $0.rings.flatMap{$0} } + roadRings.flatMap{$0} + turns.compactMap(\.position) + sectorMarkers.map(\.position) + zoneAnnotations.map(\.position) + (informationMarkers ?? []).map(\.position) + (operationalRings ?? []).flatMap(\.points)
        return !roadRings.isEmpty && roadRings.allSatisfy{$0.count >= 3} && points.allSatisfy{$0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)} && Set(turns.map(\.number)).count == turns.count
    }
}
public protocol EventMetadataDocument:Decodable {var season:Int{get};var eventKey:String{get}}
public struct CircuitDocument: Codable, EventMetadataDocument {
    public let schemaVersion: Int; public let season: Int; public let eventKey: String
    public let identity: Researched<EventIdentity>; public let circuitLengthKm: Researched<Double>?; public let raceLaps: Researched<Int>?
    public let geometry: Researched<MetadataGeometry>?; public let sectorLengthsKm: Researched<[Double]>?
    public let startFinish: Researched<TrackPoint>?; public let pitEntry: Researched<TrackPoint>?; public let pitExit: Researched<TrackPoint>?
}
public struct TyrePressure: Codable { public let frontPsi: Double; public let rearPsi: Double }
public struct PressureRevision: Codable { public let frontPsi: Double; public let rearPsi: Double; public let publishedAtLocal: String; public let effectiveFrom: String? }
public struct TyreDocument: Codable, EventMetadataDocument {
    public let season: Int; public let eventKey: String; public let dryCompounds: Researched<[String]>?
    public let minimumPressures: Researched<TyrePressure>?; public let revisions: [Researched<PressureRevision>]
}
public struct PitDocument: Codable, EventMetadataDocument { public let season: Int; public let eventKey: String; public let referencePitLossSeconds: Researched<Double>?; public let pitSpeedLimitKph: Researched<Double>? }
public struct EnergyDocument: Codable, EventMetadataDocument { public let season: Int; public let eventKey: String; public let raceRechargeLimit: Researched<Double>?; public let overtakeRechargeLimit: Researched<Double>?; public let qualifyingRechargeLimit: Researched<Double>?; public let units: String? }
public struct ModeActivation: Codable { public let label: String; public let description: String? }
public struct StraightLineMode: Codable { public let enabled: Bool; public let normalGripActivations: [ModeActivation]; public let lowGripActivations: [ModeActivation] }
public struct OvertakeMode: Codable { public let detection: String; public let activation: String }
public struct RaceZoneDocument: Codable, EventMetadataDocument { public let season: Int; public let eventKey: String; public let straightLineMode: Researched<StraightLineMode>?; public let overtakeMode: Researched<OvertakeMode>? }
public struct MetadataSource: Codable, Identifiable {
    public let id: String; public let tier: Int; public let publisher: String; public let title: String; public let url: String; public let retrievedAt: String
    public let confidence: String; public let supports: [String]
}
public struct SourceDocument: Codable, EventMetadataDocument { public let season: Int; public let eventKey: String; public let asOf: String; public let sources: [MetadataSource]; public let notes: [String] }
public struct EventTrackMetadata {
    public let circuit: CircuitDocument; public let zones: RaceZoneDocument?; public let tyres: TyreDocument?; public let pit: PitDocument?; public let energy: EnergyDocument?; public let provenance: SourceDocument
    public var operationalMarkers:[MetadataMarker] {
        [("S/F",circuit.startFinish),("PIT IN",circuit.pitEntry),("PIT OUT",circuit.pitExit)].compactMap { label,fact in
            guard let fact,fact.isOfficial,(0...1).contains(fact.value.x),(0...1).contains(fact.value.y),fact.sourceIds.contains(where:{id in provenance.sources.contains{$0.id==id && $0.tier==1}}) else{return nil}
            return MetadataMarker(label:label,position:fact.value)
        }
    }
    public var geometry: MetadataGeometry? {
        guard let fact = circuit.geometry, fact.isOfficial, fact.value.valid,
              fact.sourceIds.contains(where:{ id in provenance.sources.contains{$0.id == id && $0.tier == 1} }) else { return nil }
        return fact.value
    }
}
/// Only bundled, season-scoped documents are read. No web requests or loose JSON in views.
public final class TrackMetadataRepository {
    public let root: URL?
    public let calendar: MetadataCalendar?
    private var cached: [String:EventTrackMetadata] = [:]
    public init(root: URL?) {
        self.root = root
        calendar = root.flatMap { Self.read(MetadataCalendar.self,$0.appendingPathComponent("calendar.json")) }
    }
    static private func read<T:Decodable>(_ type:T.Type,_ url:URL)->T? {
        guard let data=try? Data(contentsOf:url) else{return nil}
        return try? JSONDecoder().decode(type,from:data)
    }
    private func readEvent<T:EventMetadataDocument>(_ type:T.Type,_ folder:URL,_ name:String,season:Int,key:String)->T? {
        guard let doc=Self.read(type,folder.appendingPathComponent(name+".json")),doc.season==season,doc.eventKey==key else{return nil}
        return doc
    }
    public func load(season:Int=2026,eventKey:String)->EventTrackMetadata? {
        guard calendar?.season==season,calendar?.events.contains(where:{$0.eventKey==eventKey})==true,let root else{return nil}
        let key="\(season)/\(eventKey)";if let old=cached[key]{return old}
        let folder=root.appendingPathComponent(key)
        guard let circuit=Self.read(CircuitDocument.self,folder.appendingPathComponent("circuit.json")),
              let sources=Self.read(SourceDocument.self,folder.appendingPathComponent("sources.json")),
              circuit.schemaVersion==1,circuit.season==season,circuit.eventKey==eventKey,sources.season==season,sources.eventKey==eventKey else{return nil}
        let value=EventTrackMetadata(circuit:circuit,zones:readEvent(RaceZoneDocument.self,folder,"race_zones",season:season,key:eventKey),tyres:readEvent(TyreDocument.self,folder,"tyres",season:season,key:eventKey),pit:readEvent(PitDocument.self,folder,"pit",season:season,key:eventKey),energy:readEvent(EnergyDocument.self,folder,"energy",season:season,key:eventKey),provenance:sources)
        cached[key]=value;return value
    }
}

