import SwiftUI

struct TrackLibraryView: View {
    let repository: TrackMetadataRepository
    var session: SessionState?
    @Environment(\.dismiss) private var dismiss
    @State private var selected="japan"
    var body: some View {
        VStack(spacing:12) {
            HStack { Text("Circuit reference").font(.title2.bold());Spacer();Button("Done"){dismiss()} }
            Picker("Grand Prix",selection:$selected) {
                ForEach(repository.calendar?.events ?? []) { event in Text(L10n.text(event.meetingName)).tag(event.eventKey) }
            }.accessibilityIdentifier("metadataEventPicker")
            if let data=repository.load(eventKey:selected) {
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        HStack { Text(L10n.text(data.circuit.identity.value.circuitName)).font(.headline);Spacer();Text("2026") }
                        if let geometry=data.geometry { StaticCircuitMap(geometry:geometry,markers:data.operationalMarkers).frame(height:310).accessibilityIdentifier("staticCircuit-\(selected)") }
                        Text("Official reference map · car positions use their own source coordinates").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            if let length=data.circuit.circuitLengthKm { Text(String(format:"%.3f km",length.value)) }
                            if let laps=data.circuit.raceLaps { Text("Lap count: \(laps.value)") }
                            if let sectors=data.circuit.sectorLengthsKm { Text(sectors.value.enumerated().map{String(format:"S%d %.3f km",$0.offset+1,$0.element)}.joined(separator:" · ")).font(.caption) }
                        }
                        if let zones=data.zones?.straightLineMode,zones.isOfficial {
                            section("Straight Mode") {
                                if !zones.value.enabled { Text("Not used at this event") }
                                else {
                                    Text("Normal grip").font(.caption.bold())
                                    ForEach(zones.value.normalGripActivations,id:\.label){z in Text(z.label+z.description.map{" · "+L10n.zone($0)}.orEmpty)}
                                    Text("Low grip").font(.caption.bold())
                                    ForEach(zones.value.lowGripActivations,id:\.label){z in Text(z.label+z.description.map{" · "+L10n.zone($0)}.orEmpty)}
                                }
                            }
                        }
                        if let ot=data.zones?.overtakeMode,ot.isOfficial {
                            section("Overtake Mode") { Text(L10n.text("Detection")+"："+L10n.zone(ot.value.detection));Text(L10n.text("Activation")+"："+L10n.zone(ot.value.activation)) }
                        }
                        section("Weekend tyres") {
                            Text(data.tyres?.dryCompounds?.value.joined(separator:" / ") ?? L10n.text("Not published"))
                            if let revisions=data.tyres?.revisions,!revisions.isEmpty {
                                Text("Minimum starting pressure · front / rear").font(.caption.bold())
                                ForEach(Array(revisions.enumerated()),id:\.offset){_,r in
                                    HStack { Text(r.value.publishedAtLocal.replacingOccurrences(of:"T",with:" "));Spacer();Text(String(format:"%.1f / %.1f psi",r.value.frontPsi,r.value.rearPsi)).monospacedDigit() }
                                }
                                Text("Publication time in the source document; effective session is not inferred.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        section("Energy and pit lane") {
                            if let e=data.energy {
                                energyRow("Race recharge",e.raceRechargeLimit);energyRow("Overtake recharge",e.overtakeRechargeLimit);energyRow("Qualifying recharge",e.qualifyingRechargeLimit)
                            }
                            if let pit=data.pit?.referencePitLossSeconds { Text(L10n.text("Reference pit loss")+String(format:" ≈ %.1f s",pit.value)+" · "+L10n.text(pit.isOfficial ? "Official source" : "Secondary source")) }
                            if let speed=data.pit?.pitSpeedLimitKph { Text(L10n.text("Pit speed limit")+String(format:" %.0f km/h",speed.value)) }
                        }
                        DisclosureGroup("Sources and verification") {
                            VStack(alignment:.leading,spacing:8) {
                                Text(L10n.text("Verified as of")+" "+data.provenance.asOf)
                                ForEach(data.provenance.sources) { s in if let url=URL(string:s.url) { Link(s.publisher+" · "+L10n.text(s.tier==1 ? "Official source" : "Secondary source"),destination:url) } }
                                Text("Unverified coordinates and unpublished values are omitted.").font(.caption)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }.padding(4)
                }
            } else { ContentUnavailableView("Metadata unavailable",systemImage:"map") }
        }.padding(20).frame(minWidth:560,idealWidth:630,maxWidth:900,minHeight:640,idealHeight:750,maxHeight:1000)
            .onAppear{if let session,let data=repository.resolve(session){selected=data.circuit.eventKey}}
    }
    private func section<Content:View>(_ title:LocalizedStringKey,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:6){Text(title).font(.headline);content()}.frame(maxWidth:.infinity,alignment:.leading).padding(10).cardSurface()
    }
    @ViewBuilder private func energyRow(_ label:String,_ value:Researched<Double>?)->some View { if let value { HStack {Text(L10n.text(label));Spacer();Text(String(format:"%.1f MJ",value.value))} } }
}
private extension Optional where Wrapped == String { var orEmpty:String { self ?? "" } }
struct StaticCircuitMap: View {
    let geometry: MetadataGeometry
    var markers:[MetadataMarker]=[]
    var layers: MapLayers? = nil
    var safetyFlags:[Int:String]=[:]
    var raceControlFlags:[Int:String]=[:]
    var phase:RacePhase = .green
    var cars:[MapCar]=[]
    var safetyLines:[MapSafetyLine]=[]
    var drsLines:[MapDRSLine]=[]
    var centerline=false
    var calibrated=false
    var qualifying=false
    var sampledFinish:TrackPoint?
    var qualifyingStrokes:[QualifyingSectorStroke]=[]
    var qualifyingEmphasis:[Int:TimingMerit]=[:]
    var timingSafetyActive:Bool {phase == .red || (Array(safetyFlags.values)+Array(raceControlFlags.values)).contains(where:{$0 == "RED" || $0.contains("YELLOW")})}
    @Environment(\.colorScheme) private var colorScheme
    @State private var lowGrip=false
    var body: some View {
        VStack(spacing:4) {
            if layers == nil && geometry.zoneAnnotations.contains(where:{$0.kind.hasPrefix("slm")}) {
                Picker("Grip conditions",selection:$lowGrip){Text("Normal grip").tag(false);Text("Low grip").tag(true)}.pickerStyle(.segmented).frame(maxWidth:240).controlSize(.small)
            }
            Canvas { context,size in
                let projection=MapProjection(points:geometry.roadRings.flatMap{$0},size:size)
                func p(_ a:TrackPoint)->CGPoint {projection.point(a)}
                func path(_ points:[TrackPoint])->Path { Path { line in if let first=points.first {line.move(to:p(first));for a in points.dropFirst(){line.addLine(to:p(a))};line.closeSubpath()} } }
                var road=Path();for ring in geometry.roadRings{road.addPath(path(ring))}
                if centerline {context.stroke(road,with:.color(.primary.opacity(0.60)),style:.init(lineWidth:3,lineCap:.round,lineJoin:.round))}
                else {context.fill(road,with:.color(.primary.opacity(0.72)),style:FillStyle(eoFill:true))}
                for ring in geometry.operationalRings ?? [] where (ring.kind == "slmLowGrip" ? (layers?.contains(.lowGrip) ?? lowGrip) : (layers?.contains(.straightMode) ?? !lowGrip)) {context.fill(path(ring.points),with:.color((ring.kind == "slmLowGrip" ? Color.blue:Color.cyan).opacity(0.35)))}
                if layers?.contains(.sectors) ?? true {
                    for area in geometry.timingSectorAreas ?? [] {for ring in area.rings {context.fill(path(ring),with:.color([Color.blue,.purple,.teal][(area.number-1)%3].opacity(0.20)))}}
                    for sector in qualifyingStrokes {
                        var line=Path();if let first=sector.points.first {line.move(to:p(first));for point in sector.points.dropFirst(){line.addLine(to:p(point))}}
                        let base=[Color(hex:"668BB7"),Color(hex:"B492BF"),Color(hex:"74ADAF")][(sector.number-1)%3]
                        context.stroke(line,with:.color(base),style:.init(lineWidth:4,lineCap:.round,lineJoin:.round))
                        if !timingSafetyActive,let merit=qualifyingEmphasis[sector.number] {
                            context.stroke(line,with:.color(merit.color(colorScheme)),style:.init(lineWidth:6,lineCap:.round,lineJoin:.round))
                        }
                    }
                }
                for zone in drsLines {
                    if layers?.contains(.drsActivation) == true {
                        var line=Path();if let first=zone.points.first {line.move(to:p(first));for point in zone.points.dropFirst(){line.addLine(to:p(point))}}
                        context.stroke(line,with:.color(zone.enabled ? .green:.gray),style:.init(lineWidth:4,lineCap:.round,dash:[6,3]))
                    }
                    if layers?.contains(.drsDetection) == true,let point=zone.detection {let q=p(point);context.stroke(Path(ellipseIn:CGRect(x:q.x-4,y:q.y-4,width:8,height:8)),with:.color(.green),lineWidth:2)}
                }
                for segment in safetyLines {
                    var line=Path()
                    if let first=segment.points.first {line.move(to:p(first));for point in segment.points.dropFirst(){line.addLine(to:p(point))}}
                    context.stroke(line,with:.color(segment.flag == "RED" ? .red:.yellow),style:.init(lineWidth:segment.flag == "DOUBLE YELLOW" ? 9:6,lineCap:.round,lineJoin:.round))
                }
                // Strongest factual safety overlay wins across both independent scopes.
                let activeAreas=((geometry.timingSectorAreas ?? []).map{($0,safetyFlags[$0.number] ?? "")} + (geometry.raceControlAreas ?? []).map{($0,raceControlFlags[$0.number] ?? "")})
                    .filter{["RED","DOUBLE YELLOW","YELLOW"].contains($0.1)}.sorted{MapSafetyPriority.rank($0.1)<MapSafetyPriority.rank($1.1)}
                var safetyContext=context
                if !centerline {safetyContext.clip(to:road,style:FillStyle(eoFill:true))}
                for (area,flag) in activeAreas {
                    for ring in area.rings {safetyContext.fill(path(ring),with:.color(flag=="RED" ? .red:.yellow));safetyContext.stroke(path(ring),with:.color((flag=="RED" ? Color.red:.yellow).opacity(0.55)),lineWidth:flag=="DOUBLE YELLOW" ? 5:2)}
                }
                if phase == .red {context.stroke(road,with:.color(.red),style:.init(lineWidth:4,lineCap:.round,lineJoin:.round))}
                // Even when dense text cannot fit, its factual anchor remains on the map.
                for marker in geometry.informationMarkers ?? [] where layers?.contains(MapLayer(rawValue:marker.kind) ?? .corners) ?? false {
                    let q=p(marker.position);context.fill(Path(ellipseIn:CGRect(x:q.x-1.7,y:q.y-1.7,width:3.4,height:3.4)),with:.color(.primary))
                }
                let labels=placedLabels(size:size)
                for item in labels {
                    let at=CGPoint(x:item.rect.midX,y:item.rect.midY)
                    if at != item.anchor {
                        var line=Path();line.move(to:item.anchor);line.addLine(to:at)
                        context.stroke(line,with:.color(item.color.opacity(0.55)),lineWidth:0.65)
                    }
                    if item.technical {context.fill(Path(ellipseIn:CGRect(x:item.anchor.x-1.7,y:item.anchor.y-1.7,width:3.4,height:3.4)),with:.color(item.color))}
                    context.draw(Text(item.text).font(.system(size:item.font,weight:item.technical ? .medium:.bold)).foregroundColor(item.color),at:at)
                }
                for car in cars.sorted(by:{!$0.selected && $1.selected}) {
                    let q=p(car.point),radius:CGFloat=car.selected ? 8:5
                    let dot=Path(ellipseIn:CGRect(x:q.x-radius,y:q.y-radius,width:radius*2,height:radius*2))
                    context.fill(dot,with:.color(Color(hex:car.color).opacity(car.retired ? 0.35:1)))
                    context.stroke(dot,with:.color(car.selected ? .primary:colorScheme == .dark ? .black:.white),lineWidth:car.selected ? 2.5:1)

                }
            }.overlay {GeometryReader { proxy in
                ForEach(Array(placedLabels(size:proxy.size).enumerated()),id:\.offset) { _,item in
                    Color.clear.frame(width:item.rect.width+4,height:item.rect.height+4).contentShape(Rectangle()).position(x:item.rect.midX,y:item.rect.midY).help(item.help).accessibilityElement(children:.ignore).accessibilityLabel(item.text).accessibilityIdentifier("staticLabel-"+item.text).accessibilityValue(String(format:"%.3f,%.3f",item.rect.midX,item.rect.midY))
                }
            }}.accessibilityElement(children:.contain).accessibilityLabel(L10n.text(calibrated ? "Calibrated circuit map" : "Circuit map")+" · "+L10n.text("Cars")+": \(cars.count)").accessibilityValue((raceControlFlags.keys.sorted().map{"RC\($0) · \(raceControlFlags[$0] ?? "")"}+qualifyingStrokes.map{"S\($0.number) lane · \(timingSafetyActive ? "safety priority":qualifyingEmphasis[$0.number]?.rawValue ?? "sector tint")"}).joined(separator:"; "))
        }.padding(6).background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:12))
    }
    private struct PlacedLabel {var text:String;var help:String;var anchor:CGPoint;var rect:CGRect;var color:Color;var font:CGFloat;var technical:Bool}
    private func placedLabels(size:CGSize)->[PlacedLabel] {
        let projection=MapProjection(points:geometry.roadRings.flatMap{$0},size:size)
        func project(_ a:TrackPoint)->CGPoint {projection.point(a)}
        var occupied:[CGRect]=[] // Static metadata never negotiates space with moving cars.
        var result:[PlacedLabel]=[]
        func add(_ text:String,_ point:TrackPoint,_ meaning:String,_ color:Color = .primary,_ font:CGFloat = 9,_ technical:Bool = true) {
            let factual=MapAnnotationAnchor(id:meaning+"-"+text,canonicalCoordinate:point)
            let anchor=project(factual.canonicalCoordinate)
            guard let rect=MapLabelLayout.place(anchor:anchor,size:CGSize(width:CGFloat(text.count)*font*0.66+5,height:font+5),bounds:size,occupied:&occupied,technical:technical) else{return}
            result.append(.init(text:text,help:text+" · "+L10n.text(meaning),anchor:anchor,rect:rect,color:color,font:font,technical:technical))
        }
        if let sampledFinish {add("S3",sampledFinish,"Lap boundary · recorded location sample",colorScheme == .dark ? .yellow:Color(hex:"765400"),16,true)}
        if qualifying {
        for s in geometry.sectorMarkers where layers?.contains(.sectors) ?? true {add(s.label,s.position,"Timing sector boundary",colorScheme == .dark ? .yellow:Color(hex:"765400"),qualifying ? 16:12,false)}
        }
        // Critical sector labels claim space before optional engineering detail.
        for area in geometry.raceControlAreas ?? [] where layers?.contains(.raceControl) == true {
            if let ring=area.rings.max(by:{$0.count<$1.count}),let point=ring.first {add("RC\(area.number)",point,"RC · Race Control sector",(raceControlFlags[area.number]?.contains("YELLOW") == true ? (colorScheme == .dark ? .yellow:Color(hex:"765400")):.secondary),10,false)}
        }
        if !qualifying {
        for s in geometry.sectorMarkers where layers?.contains(.sectors) ?? true {add(s.label,s.position,"Timing sector boundary",colorScheme == .dark ? .yellow:Color(hex:"765400"),qualifying ? 16:12,false)}
        }
        for marker in markers where layers?.contains(marker.label == "S/F" ? .startFinish:.pit) ?? true {add(L10n.text(marker.label),marker.position,marker.label == "S/F" ? "Start / finish":"Pit entry / exit",.primary,10,false)}
        for (index,t) in geometry.turns.enumerated() where layers?.contains(.corners) ?? true {
            if layers?.density == .simple && layers?.overrides[.corners] == nil && index%3 != 0 {continue}
            if let point=t.position {add(t.label,point,"Turn number",.primary,10,false)}
        }
        for marker in geometry.informationMarkers ?? [] where layers?.contains(MapLayer(rawValue:marker.kind) ?? .corners) ?? false {add(marker.label,marker.position,MapLayer(rawValue:marker.kind)?.title ?? marker.label)}
        for z in geometry.zoneAnnotations {
            let layer:MapLayer=z.kind.hasPrefix("drs") ? (z.kind == "drsDetection" ? .drsDetection:.drsActivation):z.kind == "overtake" ? (z.label.contains("D") ? .overtakeDetection:.overtakeActivation):z.kind == "slmLowGrip" ? .lowGrip:.straightMode
            guard layers?.contains(layer) ?? (layer != .lowGrip) else {continue}
            add(z.label,z.position,layer.title,(z.kind=="overtake" || z.kind.hasPrefix("drs")) ? (colorScheme == .dark ? .green:Color(hex:"007D31")):.primary,8)
        }
        return result
    }

}
