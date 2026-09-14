import Foundation
@_exported import RaceCardDataKit

extension TrackMetadataRepository {
    convenience init() {self.init(root:Bundle.main.resourceURL?.appendingPathComponent("TrackMetadata"))}
    func resolve(_ session:SessionState)->EventTrackMetadata? {
        let year=Calendar(identifier:.gregorian).component(.year,from:session.start)
        guard year==calendar?.season,let event=calendar?.events.first(where:{$0.meetingKey==session.meeting}) else{return nil}
        return load(season:year,eventKey:event.eventKey)
    }
}

struct LegacyCircuitDocument: Decodable {
    let season:Int;let sessionKey:Int;let geometry:MetadataGeometry;let source:MetadataSource
    private static let bundled:Self? = {
        guard let url=Bundle.main.resourceURL?.appendingPathComponent("TrackMetadata/legacy_singapore_2023.json"),let data=try? Data(contentsOf:url),let doc=try? JSONDecoder().decode(Self.self,from:data),doc.source.tier==1,doc.geometry.valid else{return nil};return doc
    }()
    static func load(session:Int)->Self? {session==9165 ? bundled : nil}
}
