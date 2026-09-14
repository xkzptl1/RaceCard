import SwiftUI

struct OperationalMap: View {
    var store: RaceStateStore; var textSize: CGFloat
    var onBackgroundTap: ()->Void = {}
    var reference: EventTrackMetadata?
    var metadataRoot:URL?
    var qualifyingTiming:QualifyingDriverTiming? = nil
    @State private var layers=MapLayers()
    @State private var layersOpen=false
    @State private var legendOpen=false
    var scene:CanonicalMap {CanonicalMap(store:store,reference:reference,metadataRoot:metadataRoot,layers:layers,onBackgroundTap:onBackgroundTap,qualifyingTiming:qualifyingTiming)}
    var sourceGeometry:MetadataGeometry? {scene.calibration == nil || scene.calibration?.canonicalCenterline != nil ? nil:scene.officialGeometry}
    var availableLayers:[MapLayer] {
        var result:[MapLayer]=[.cars]
        if let m=store.metadata {
            if !m.sectors.isEmpty {result.append(.sectors)}
            if !m.corners.isEmpty {result.append(.corners)}
            if m.startFinish != nil {result.append(.startFinish)}
            if m.pitEntry != nil || m.pitExit != nil {result.append(.pit)}
            if !m.drsZones.isEmpty && Calendar.current.component(.year,from:store.session?.start ?? Date())<2026 {result += [.drsDetection,.drsActivation]}
        }
        if let g=sourceGeometry {

            for marker in g.informationMarkers ?? [] {if let layer=MapLayer(rawValue:marker.kind) {result.append(layer)}}
            if g.zoneAnnotations.contains(where:{$0.kind=="drsDetection"}) {result += [.drsDetection,.drsActivation]}
            if !(g.raceControlAreas ?? []).isEmpty {result.append(.raceControl)}
            if !g.sectorMarkers.isEmpty {result.append(.sectors)}
            if !g.turns.isEmpty {result.append(.corners)}
            for marker in scene.officialMarkers {result.append(marker.label == "S/F" ? .startFinish : .pit)}
            if g.zoneAnnotations.contains(where:{$0.kind=="overtake"}) {result += [.overtakeDetection,.overtakeActivation]}
            if g.zoneAnnotations.contains(where:{$0.kind=="slmNormal"}) {result.append(.straightMode)}
            if g.zoneAnnotations.contains(where:{$0.kind=="slmLowGrip"}) {result.append(.lowGrip)}
        }
        return MapLayer.allCases.filter{result.contains($0)}
    }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing:5) {
            HStack {
                Text("TRACK POSITION").font(.system(size:11,weight:.bold))
                Spacer()
                Button {layersOpen.toggle()} label: {Label("Map layers",systemImage:"square.3.layers.3d")}.font(.system(size:10)).controlSize(.small).accessibilityIdentifier("mapLayer")
                    .popover(isPresented:$layersOpen){MapLayersPopover(layers:layers,available:availableLayers,onDone:{layersOpen=false}).onExitCommand{layersOpen=false}.environment(\.locale,Locale(identifier:Localization.shared.language))}
                Button {legendOpen.toggle()} label:{Image(systemName:"questionmark.circle")}.buttonStyle(.plain).accessibilityLabel("Map legend").accessibilityIdentifier("mapLegend")
                    .popover(isPresented:$legendOpen) {VStack(alignment:.leading,spacing:8) {
                        Text(L10n.text("Map legend")).font(.headline)
                        ForEach(availableLayers.filter{$0 != .cars},id:\.self) {layer in Text(L10n.text(layer.title)).font(.caption)}
                        if availableLayers.contains(.corners) {Text(L10n.text("T · Turn number")).font(.caption)}
                        if availableLayers.contains(.sectors) {Text(L10n.text("S · Timing sector boundary")).font(.caption)}
                        if availableLayers.contains(.raceControl) {Text(L10n.text("RC · Race Control sector")).font(.caption)}
                        if availableLayers.contains(.lightPanels) {Text(L10n.text("LP · FIA light panel")).font(.caption)}
                        if availableLayers.contains(.overtakeActivation) {Text(L10n.text("OT · Overtake detection / activation")).font(.caption)}
                        if availableLayers.contains(.straightMode) {Text(L10n.text("SM · Straight Mode")).font(.caption)}
                        Text(L10n.text("S · Soft   M · Medium   H · Hard   I · Intermediate   W · Wet")).font(.caption)
                        if store.session?.isQualifying == true {Text(L10n.text("Sector lanes use fixed tints. Recent completed sectors briefly show the map driver’s purple/green timing. Safety warnings take priority.")).font(.caption)}
                        Text(L10n.text("Hover a label for its meaning. Lines connect labels to verified positions.")).font(.caption).foregroundStyle(.secondary)
                    }.padding(16).frame(maxWidth:330)}
                if alertNotice == nil,let phase = phaseChip { Label(L10n.text(phase.0),systemImage:phase.1).font(.system(size:11,weight:.bold)).padding(.horizontal,8).padding(.vertical,4).background(phase.2.opacity(0.25),in:Capsule()).accessibilityIdentifier("racePhaseChip") }
            }.frame(height:26)
            scene
                .overlay(alignment:.top) {
                    GeometryReader { proxy in
                        VStack(spacing:0) {
            if store.session?.isRace == true,let lights=store.raceStart.lightState(at:store.currentTime) {
                HStack(spacing:9) {
                    ForEach(0..<5) { i in Circle().fill(i < lights.illuminated ? Color.red : Color.gray.opacity(0.3)).overlay(Circle().stroke(.white.opacity(0.6))).frame(width:23,height:23) }
                }.padding(9).background(.black.opacity(0.85),in:RoundedRectangle(cornerRadius:8))
                    .opacity(lights.opacity).accessibilityElement(children:.ignore)
                    .accessibilityLabel(L10n.text("Start lights")+" · "+String(lights.illuminated)+" / 5")
                    .accessibilityIdentifier("startLightHousing")
            }
                            else if let notice=alertNotice {
                                MapAlertArea(notice:notice,store:store,textSize:textSize)
                                    .accessibilityIdentifier("mapAlertArea")
                            }
                        }.frame(width:proxy.size.width * 0.7)
                            .frame(maxWidth:.infinity,alignment:.top).padding(.top,16)
                            .offset(x:scene.alertHorizontalOffset(size:proxy.size))
                    }.allowsHitTesting(false)
                }
                .accessibilityElement(children:.contain).accessibilityIdentifier("mapContent")
            HStack { Text(L10n.text(metadataSummary));if let timing=qualifyingTiming,let driver=store.drivers[timing.driver] {Text(L10n.text("Map timing")+" · "+driver.acronym)};Spacer();if let sector=store.raceControl.sector { Text(L10n.text("RC\(sector) · \(store.raceControl.flag)")) } }.font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }.padding(12)
    }
    var alertNotice:MapNotice? {
        if let notice=store.visibleNotice {return notice}
        if store.raceStart.phase == .formationLap {return .init(id:"formation",category:"FORMATION LAP",text:L10n.text("Formation lap"))}
        if store.raceStart.phase == .gridForming {return .init(id:"grid",category:"GRID FORMING",text:L10n.text("Forming the starting grid"))}
        return nil
    }
    var metadataSummary: String {
        if store.positionDataUnavailable {return store.positionDataMessage ?? "Car positions unavailable · cached timing continues"}
        if !availableLayers.contains(.raceControl),store.raceControl.sectorFlags.values.contains(where:{$0.contains("YELLOW")}) {return "RC geometry unavailable"}

        if scene.calibration != nil {return "Calibrated circuit map"}

        guard let m=store.metadata,m.verified else { return "OpenF1 XY · static overlays unavailable" }
        var labels = m.sectors.isEmpty ? [String]() : ["S1 / S2 / S3"]
        if !m.drsZones.isEmpty && availableLayers.contains(.drsDetection) { labels.append("DRS") }
        if m.pitEntry != nil || m.pitExit != nil { labels.append("PIT") }
        if m.coordinateSession != nil { labels.append(L10n.text("OpenF1 sampled")) }
        return labels.joined(separator:" · ")
    }
    var phaseChip: (String,String,Color)? {
        if store.session?.isQualifying == true,store.raceControl.phase == .finished {
            if store.raceControl.sectorFlags.values.contains("DOUBLE YELLOW") {return ("DOUBLE YELLOW","flag.fill",.yellow)}
            if store.raceControl.sectorFlags.values.contains(where:{$0.contains("YELLOW")}) {return ("YELLOW","flag.fill",.yellow)}
        }
        switch store.raceControl.phase { case .safetyCar:return (store.safetyEnding ? "SC · IN THIS LAP":"SC · SAFETY CAR","flag.fill",.yellow);case .virtualSafetyCar:return (store.safetyEnding ? "VSC · ENDING":"VSC","flag.fill",.yellow);case .red:return ("Session suspended","flag.fill",.red);case .finished:return (store.session?.isQualifying == true ? "Phase complete":"FINISHED","flag.checkered",.gray);case .green:if store.raceControl.sectorFlags.values.contains("DOUBLE YELLOW") {return ("DOUBLE YELLOW","flag.fill",.yellow)};if store.raceControl.sectorFlags.values.contains(where:{$0.contains("YELLOW")}) {return ("YELLOW","flag.fill",.yellow)};return nil }
    }
}
