import SwiftUI
import RaceCardDataKit

struct MapDRSLine {var points:[TrackPoint];var detection:TrackPoint?;var enabled:Bool}
struct MapSafetyLine {var points:[TrackPoint];var flag:String}
struct MapCar:Identifiable {
    var id:Int;var point:TrackPoint;var color:String;var label:String;var selected:Bool;var retired:Bool
}
struct CanonicalMap:View {
    var store:RaceStateStore
    var reference:EventTrackMetadata?
    var metadataRoot:URL?
    var layers:MapLayers
    var onBackgroundTap:()->Void
    var qualifyingTiming:QualifyingDriverTiming? = nil
    var mapReference:EventTrackMetadata? {
        if let reference {return reference}
        let repository=TrackMetadataRepository(root:metadataRoot)
        guard let event=repository.calendar?.events.first(where:{$0.circuitName == store.session?.circuit}) else{return nil}
        return repository.load(eventKey:event.eventKey)
    }
    var calibration:CircuitCoordinateTransform? {
        guard let reference=mapReference,let root=metadataRoot else{return nil}
        let specific=root.appendingPathComponent("calibrations/"+reference.circuit.eventKey+"-"+String(store.session?.id ?? 0)+".json")
        let file=FileManager.default.fileExists(atPath:specific.path) ? specific:root.appendingPathComponent("calibrations/"+reference.circuit.eventKey+".json")
        guard let transform=CanonicalMapAssets.transform(file),transform.isValid else{return nil}
        // Calibrations are session-scoped until another session is independently verified.
        if transform.sessionKey == store.session?.id {return transform}
        return transform.validated(for:store.track.map{.init(x:$0.x,y:$0.y)},session:store.session?.id ?? 0,sourceURL:"https://api.openf1.org/v1/location?session_key=\(store.session?.id ?? 0)")
    }
    var officialGeometry:MetadataGeometry? {
        if let path=calibration?.staticGeometryPath,MetadataValidator.safePath(path),let root=metadataRoot,let geometry=CanonicalMapAssets.geometry(root.appendingPathComponent(path)),geometry.valid {return geometry}
        guard let geometry=mapReference?.geometry else {return nil}
        // A geometrically matching lap does not verify another season's rules.
        guard Calendar.current.component(.year,from:store.session?.start ?? Date()) == mapReference?.circuit.season else {
            return MetadataGeometry(coordinateSpace:geometry.coordinateSpace,roadRings:geometry.roadRings)
        }
        return geometry
    }
    var officialMarkers:[MetadataMarker] {
        guard calibration?.staticGeometryPath == nil,Calendar.current.component(.year,from:store.session?.start ?? Date()) == mapReference?.circuit.season else{return []}
        return mapReference?.operationalMarkers ?? []
    }
    /// Predefined upper alert zones are evaluated against immutable circuit geometry.
    /// Neither replay state nor vehicle positions can move the overlay or the circuit.
    func alertHorizontalOffset(size:CGSize)->CGFloat {
        let points:[TrackPoint]
        if let line=calibration?.canonicalCenterline {points=line}
        else if calibration != nil,let geometry=officialGeometry {points=geometry.roadRings.flatMap{$0}}
        else {
            let xs=store.track.map(\.x),ys=store.track.map(\.y)
            let x0=xs.min() ?? 0,y1=ys.max() ?? 1
            let span=max(1,max((xs.max() ?? 1)-x0,y1-(ys.min() ?? 0)))
            points=store.track.map{TrackPoint(x:($0.x-x0)/span,y:(y1-$0.y)/span)}
        }
        guard !points.isEmpty else{return 0}
        let projection=MapProjection(points:points,size:size)
        let rendered=points.map{projection.point($0)}
        let width=min(size.width*0.7,350)
        func obstruction(_ fraction:CGFloat)->Int {
            let zone=CGRect(x:size.width*fraction-width/2,y:6,width:width,height:76)
            return rendered.filter{zone.contains($0)}.count
        }
        let centered=obstruction(0.5)
        guard centered>0 else{return 0}
        let choice:[CGFloat]=[0.5,0.35,0.65]
        let best=choice.min{obstruction($0)<obstruction($1)} ?? 0.5
        return (best-0.5)*size.width
    }
    var body:some View {
        let transform=calibration
        let bounds=store.track.isEmpty ? store.drivers.values.compactMap(\.location):store.track
        let xs=bounds.map(\.x),ys=bounds.map(\.y)
        let minX=xs.min() ?? 0,maxY=ys.max() ?? 1
        let span=max(1,max((xs.max() ?? 1)-minX,maxY-(ys.min() ?? 0)))
        let normalize:(TrackPoint)->TrackPoint = {point in
            transform?.apply(point) ?? .init(x:(point.x-minX)/span,y:(maxY-point.y)/span)
        }
        let geometry=transform?.canonicalCenterline.map{MetadataGeometry(coordinateSpace:"OpenF1 canonical",roadRings:[$0])} ?? (transform != nil ? officialGeometry : nil)
        let local=store.metadata?.verified == true && (!store.track.isEmpty || transform != nil) ? store.metadata:nil
        let corners=(local?.corners ?? []).enumerated().map {index,corner in MetadataTurn(number:index+1,label:corner.label,position:normalize(corner.point))}
        let sectors=(local?.sectors ?? []).map {MetadataMarker(label:"S\($0.number)",position:normalize($0.label))}
        let markers:[MetadataMarker]=[("S/F",local?.startFinish),("PIT IN",local?.pitEntry),("PIT OUT",local?.pitExit)].compactMap {name,point in point.map{MetadataMarker(label:name,position:normalize($0))}}
        let safetyLines=(local?.sectors ?? []).compactMap {sector -> MapSafetyLine? in
            let flags=sector.sourceSectors.compactMap{store.raceControl.sectorFlags[$0]} + [store.raceControl.timingSectorFlags[sector.number]].compactMap{$0}
            guard let flag=flags.first(where:{$0 == "RED"}) ?? flags.first(where:{$0.contains("YELLOW")}) else{return nil}
            return MapSafetyLine(points:sector.points.map(normalize),flag:flag)
        }
        let usesLocalOverlays=geometry == nil || transform?.canonicalCenterline != nil
        let drsLines=(local?.drsZones ?? []).map{MapDRSLine(points:$0.points.map(normalize),detection:$0.detectionPoint.map(normalize),enabled:store.raceControl.drsEnabled)}
        let canonical=usesLocalOverlays ? MetadataGeometry(coordinateSpace:"OpenF1 normalized",roadRings:[transform?.canonicalCenterline ?? store.track.map{normalize(.init(x:$0.x,y:$0.y))}],turns:corners,sectorMarkers:sectors):geometry!
        // Base sector colours describe the circuit in every session, including before lights out.
        // Qualifying performance emphasis remains separate from these static lane colours.
        let sectorStrokes=QualifyingMapTiming.strokes(lap:store.track.map{normalize(.init(x:$0.x,y:$0.y))},boundaries:Dictionary(canonical.sectorMarkers.compactMap {marker -> (Int,TrackPoint)? in guard let number=Int(marker.label.dropFirst()),marker.label.hasPrefix("S") else{return nil};return (number,marker.position)},uniquingKeysWith:{first,_ in first}))
        let sectorEmphasis=QualifyingMapTiming.emphasis(qualifyingTiming,at:store.currentTime)
        TimelineView(.animation(minimumInterval:1/60,paused:store.presentationSpeed==0 && store.mode != .live)) { timeline in
            let cars:[MapCar]=layers.contains(.cars) && !store.positionDataUnavailable ? store.leaderboard.compactMap {driver in
                guard let point=store.displayPosition(driver,at:timeline.date) else{return nil}
                return MapCar(id:driver.id,point:normalize(point),color:driver.color,label:driver.acronym,selected:driver.id==store.selected,retired:["RETIRED","DNF","DNS","DSQ","STOPPED"].contains(driver.status ?? ""))
            }:[]
            StaticCircuitMap(geometry:canonical,markers:usesLocalOverlays ? markers:officialMarkers,layers:layers,safetyFlags:store.raceControl.timingSectorFlags,raceControlFlags:store.raceControl.sectorFlags,phase:store.raceControl.phase,cars:cars,safetyLines:usesLocalOverlays ? safetyLines:[],drsLines:usesLocalOverlays ? drsLines:[],centerline:geometry == nil || transform?.canonicalCenterline != nil,calibrated:transform != nil,qualifying:store.session?.isQualifying == true,sampledFinish:store.session?.isQualifying == true && !canonical.sectorMarkers.contains(where:{$0.label=="S3"}) ? store.track.first.map{normalize(.init(x:$0.x,y:$0.y))}:nil,qualifyingStrokes:sectorStrokes,qualifyingEmphasis:sectorEmphasis)
        }.contentShape(Rectangle()).onTapGesture(perform:onBackgroundTap).accessibilityIdentifier("trackMap")
    }
}

/// Immutable bundled/versioned map resources are decoded once, outside animation work.
@MainActor private enum CanonicalMapAssets {
    static var transforms:[URL:CircuitCoordinateTransform]=[:]
    static var geometries:[URL:MetadataGeometry]=[:]
    static func transform(_ url:URL)->CircuitCoordinateTransform? {
        if let cached=transforms[url] {return cached}
        guard let data=try? Data(contentsOf:url),let decoded=try? JSONDecoder().decode(CircuitCoordinateTransform.self,from:data) else{return nil}
        transforms[url]=decoded;return decoded
    }
    static func geometry(_ url:URL)->MetadataGeometry? {
        if let cached=geometries[url] {return cached}
        guard let data=try? Data(contentsOf:url),let decoded=try? JSONDecoder().decode(MetadataGeometry.self,from:data) else{return nil}
        geometries[url]=decoded;return decoded
    }
}
