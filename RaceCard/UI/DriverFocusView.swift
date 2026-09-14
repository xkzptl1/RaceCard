import SwiftUI

struct DriverFocusView: View {
    @State private var stewardDetails=false
    var model:AppModel; var driver:DriverState; var layout:CardLayout
    var compactTelemetry=false
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment:.leading,spacing:8) {
                focusHeader
                ScrollView {
                    VStack(alignment:.leading,spacing:8) {
                        telemetryStrip
                        pitTiming
                        StintHistoryView(driver:driver,maximumHeight:180)
                    }
                }.frame(height:max(130,geometry.size.height-180)).accessibilityIdentifier("focusedDetailsScroll")
                FeedView(events:model.focusedEvents,language:model.language,fontSize:layout.text).frame(maxHeight:.infinity)
            }.frame(width:geometry.size.width,height:geometry.size.height,alignment:.top)
        }.onChange(of:stewardDetails){_,open in model.focusDetailOpen=open}
            .onDisappear {model.focusDetailOpen=false}
            .onHover { model.focusHovered=$0;model.touchFocus() }
            .simultaneousGesture(TapGesture().onEnded {model.touchFocus()})
            .simultaneousGesture(DragGesture(minimumDistance:1).onChanged{_ in model.touchFocus()})
    }
    private var focusHeader:some View {
        HStack(spacing:6) {
                DriverPortrait(url:driver.headshotURL,season:season,name:DriverNameResolver.full(driver)).accessibilityIdentifier("focusedHeadshot")
                VStack(alignment:.leading,spacing:4) {
                    Text(DriverNameResolver.full(driver)).font(.system(size:layout.text,weight:.bold)).lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing:5) {TeamIdentityBadge(season:season,teamName:driver.team,teamColor:driver.color,size:18);Text(driver.team).font(.caption)}
                    if model.store.pitState(driver) != .outside {Text(model.store.pitState(driver) == .normalPit ? "PIT":L10n.text("Pit lane")+" · "+L10n.text("During red-flag suspension")).font(.system(size:10,weight:.semibold)).foregroundStyle(.blue).accessibilityIdentifier("focusedPitState")}
                }
                Spacer()
                if !driver.stewardItems.isEmpty {
                    Button(driver.stewardItems.first?.compact ?? L10n.text("Stewards")) {stewardDetails.toggle()}.font(.caption).accessibilityIdentifier("stewardDetails")
                        .popover(isPresented:$stewardDetails) {ScrollView {VStack(alignment:.leading,spacing:12) {ForEach(driver.stewardItems) {item in Text(item.text(model.language,driverName:DriverNameResolver.full(driver))).font(.caption).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled).help(item.rawMessage)}}.padding(14)}.frame(width:330,height:min(350,CGFloat(driver.stewardItems.count)*90+28)).accessibilityIdentifier("stewardDetailContent")}
                }
                Button { model.dismissFocus() } label:{Image(systemName:"xmark")}.accessibilityLabel("Close focus").accessibilityIdentifier("closeFocus")
            }
    }
    private var pitTiming:some View {
        Group {
            if let pit=driver.pits.last {
                let timing=PitTimingPresentation(stopDuration:pit.stopDuration,laneDuration:pit.laneDuration,suspended:pit.intersects(model.store.suspensions))
                VStack(alignment:.leading,spacing:4) {
                    Text(L10n.text("LATEST PIT")+" · "+L10n.text("Lap \(pit.lap)")).font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary)
                    Text(timing.primary(model.language)).font(.system(size:14,weight:.bold)).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("focusedPitStopDuration")
                    if let occupancy=timing.occupancy(model.language) {
                        Text(occupancy).font(.system(size:12)).foregroundStyle(.secondary).accessibilityIdentifier("focusedPitLaneDuration")
                        if timing.suspended {Text(L10n.text("Includes Red Flag / session suspension time")).font(.system(size:11)).foregroundStyle(.secondary)}
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(8).cardSurface().accessibilityElement(children:.contain).accessibilityIdentifier("focusedPitTiming")
            }
        }
    }
    var telemetryStrip:some View {
        let t=driver.telemetry.flatMap{$0.valid(at:model.store.currentTime) ? $0:nil}
        return VStack(spacing:4) { LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:compactTelemetry ? 6:3),spacing:6) {
            telemetryItem("Speed",t?.speed.map{String($0)},unit:"km/h")
            telemetryItem("Gear",t?.gear.map{String($0)})
            telemetryItem("RPM",t?.rpm.map{String($0)},unit:"rpm")
            telemetryItem("Throttle",t?.throttle.map{"\($0)%"})
            telemetryItem("Brake",t?.brake.map{L10n.text($0>0 ? "On":"Off")})
            telemetryItem("DRS",t?.drs.map{L10n.text([10,12,14].contains($0) ? "Open":"Closed")})
        }
            Text(t == nil ? L10n.text(model.telemetryStatus ?? "Unavailable") : "")
                .font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2)
                .frame(height:26).accessibilityIdentifier("telemetryLoadStatus")
        }.padding(8).cardSurface().accessibilityElement(children:.contain).accessibilityIdentifier("focusedTelemetry")
    }
    private func telemetryItem(_ title:String,_ value:String?,unit:String="")->some View {
        VStack(spacing:2) {
            Text(L10n.text(title)).font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
            Text(value ?? "—").font(.system(size:["Brake","DRS"].contains(title) ? 18:24,weight:.bold,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.8)
            Text(value == nil ? L10n.text("Unavailable"):unit).font(.system(size:10)).foregroundStyle(.secondary).frame(height:12)
        }.frame(maxWidth:.infinity).accessibilityElement(children:.combine).accessibilityIdentifier("telemetry-"+title)
    }
    private var season:Int {Calendar.current.component(.year,from:model.store.session?.start ?? Date())}
    private func row(_ title:String,_ count:Int)->some View { HStack {Text(L10n.text(title));Spacer();Text("\(count) laps").monospacedDigit()} }
}
