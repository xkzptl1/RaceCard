import SwiftUI

struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    @State private var flipping = false
    var body: some View {
        GeometryReader { geometry in
            let layout = CardLayout(width:geometry.size.width,height:geometry.size.height)
            VStack(spacing:8) {
                header(layout)
                if !model.loading.isEmpty { HStack { ProgressView().controlSize(.small); Text(L10n.text(model.loading)).font(.caption); Spacer() } }
                if let error = model.error { HStack { Image(systemName:"exclamationmark.triangle"); Text(L10n.failure(error)).font(.caption); Spacer(); Button { model.error = nil } label: { Image(systemName:"xmark") } }.padding(8).background(.orange.opacity(0.15),in:RoundedRectangle(cornerRadius:8)) }
                ZStack {
                    if !model.showingBack { front(layout).transition(.opacity) }
                    else { ChampionshipBackView(model:model,layout:layout).transition(.opacity) }
                }.rotation3DEffect(.degrees(angle),axis:(x:0,y:1,z:0),perspective:0.25)
            }.padding(layout.padding).accessibilityHidden(model.profile != nil).allowsHitTesting(model.profile == nil)
                .overlay {if let profile=model.profile {ProfileView(route:profile,model:model,close:{model.profile=nil})}}
        }.frame(minWidth:600,minHeight:760).background(Color(nsColor:.windowBackgroundColor))
        .preferredColorScheme(model.theme == "Light" ? .light : model.theme == "Dark" ? .dark : nil)
        .sheet(isPresented:$model.picker) { SessionPicker(model:model) }
        .sheet(isPresented:$model.metadataLibrary) { TrackLibraryView(repository:model.trackRepository,session:model.store.session).environment(\.locale,Locale(identifier:model.language)) }
        .sheet(isPresented:$model.settings) { SettingsView(model:model) }
        .sheet(isPresented:$model.inspector,onDismiss:{model.setInspector(false)}) { InspectorView(model:model) }
        .task {
            let args = ProcessInfo.processInfo.arguments
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil && !args.contains("--smoke") { return }
            guard !model.didLaunch else { return }; model.didLaunch = true
            model.mockStartLights = args.contains("--mock-start-lights")
            model.pitStartFixture = args.contains("--pit-start-fixture")
            model.timingSectorFixture = args.contains("--timing-sector-fixture")
            if let i=args.firstIndex(of:"--reference-event"),args.indices.contains(i+1){model.referenceOverride=args[i+1]}
            model.start()
            #if DEBUG
            if let i=args.firstIndex(of:"--inspect-calibration"),args.indices.contains(i+1) {model.inspectCalibration(at:URL(fileURLWithPath:args[i+1]));return}
            #endif
            if let i = args.firstIndex(of:"--historical"),args.indices.contains(i+1),let key = Int(args[i+1]) { await model.openHistoricalKey(key,replay:!args.contains("--results")) }
            if args.contains("--smoke") { model.clock.speed = 10 }
            if let i=args.firstIndex(of:"--mock-time"),args.indices.contains(i+1),let time=Double(args[i+1]) { model.seek(MockF1Provider.start.addingTimeInterval(time),resumePlaying:false) }
        }.environment(\.locale,Locale(identifier:model.language))
    }
    private func flip() {
        if reduceMotion { withAnimation(.easeOut(duration:0.12)) { model.showingBack.toggle() }; return }
        flipping = true
        withAnimation(.easeIn(duration:0.18)) { angle = 90 }
        Task { try? await Task.sleep(for:.milliseconds(180)); model.showingBack.toggle(); angle = -90; withAnimation(.easeOut(duration:0.22)) { angle = 0 }; try? await Task.sleep(for:.milliseconds(220)); flipping = false }
    }
    private func header(_ layout: CardLayout) -> some View {
        VStack(spacing:8) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4) {
                    Text(L10n.text(model.store.session?.title ?? Product.name)).font(.system(size:layout.compact ? 22 : 28,weight:.bold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    Text([L10n.text(model.store.session?.circuit ?? ""),L10n.text(model.store.session?.type ?? ""),model.store.session?.start.formatted(.dateTime.year().month().day().locale(Locale(identifier:model.language))) ?? ""].joined(separator:" · ")).font(.system(size:layout.compact ? 11 : 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength:8)
                VStack(alignment:.trailing,spacing:6) {
                    Text(badge).font(.system(size:layout.compact ? 11 : 14,weight:.bold,design:.monospaced)).accessibilityIdentifier("sessionStatus")
                    HStack(spacing:10) {
                        Button { model.setInspector(true) } label: { Image(systemName:"info.circle") }.disabled(model.store.selected == nil || !model.loading.isEmpty).accessibilityIdentifier("inspectorButton").accessibilityLabel("Driver inspector")
                        Button { model.metadataLibrary = true } label: { Image(systemName:"map") }.accessibilityIdentifier("metadataLibrary").accessibilityLabel("Circuit reference")
                        Button("Sessions") { model.picker = true }.accessibilityIdentifier("sessionsButton")
                        Button { model.settings = true } label: { Image(systemName:"gearshape") }.accessibilityIdentifier("gearshape").accessibilityLabel("Settings")
                        Button(action:flip) { Image(systemName:"rectangle.on.rectangle.angled") }.disabled(flipping).accessibilityIdentifier("flipCard").accessibilityLabel(model.showingBack ? "Race dashboard" : "Championship standings").help(model.showingBack ? "Race dashboard" : "Championship standings")
                    }.controlSize(.small)
                }
            }
            if model.store.mode != .live { replayControls }
        }
    }
    private var badge: String {
        if !model.loading.isEmpty { return L10n.text("LOADING") }
        if model.store.mode == .historical { return L10n.text("FINISHED") }
        if model.store.mode == .live { return L10n.text(model.store.connection.label(at:Date())) + " · L\(model.store.lap)" }
        return "\(L10n.text(model.store.mode == .mock ? "MOCK" : "REPLAY")) · "+replayPhaseLabel
    }
    private var replayPhaseLabel:String {
        if model.store.session?.isQualifying == true {return model.qualifying.phase.map{model.qualifyingPhaseLabel($0)} ?? L10n.text("Qualifying")}
        if model.store.session?.isRace == false {return L10n.text(model.store.session?.type ?? "Session")}
        if !model.store.raceStart.hasStarted {return L10n.text(model.store.raceStart.phase == .formationLap ? "Formation lap":"Pre-race")}
        if model.store.raceControl.phase == .finished {return L10n.text("Post-race")}
        return "L\(max(1,model.store.lap))/\(model.store.session?.totalLaps ?? 0)"
    }
    private var replayControls: some View {
        HStack(spacing:8) {
            Button("−10s") { model.seek(model.clock.time.addingTimeInterval(-10)) }
            Button { model.togglePlayback() } label: { Label(L10n.text(model.clock.playing ? "Pause" : "Play"),systemImage:model.clock.playing ? "pause.fill" : "play.fill") }.accessibilityIdentifier("playPause").accessibilityLabel(L10n.text(model.clock.playing ? "Pause" : "Play"))
            Button("+10s") { model.seek(model.clock.time.addingTimeInterval(10)) }
            Picker("Speed",selection:$model.clock.speed) { ForEach([1.0,2,5,10,50],id:\.self) { Text("\(Int($0))×").tag($0) } }.labelsHidden().frame(width:62).accessibilityIdentifier("replaySpeed")
            Slider(value:Binding(get:{model.clock.time.timeIntervalSince(model.clock.start)},set:{model.seek(model.clock.start.addingTimeInterval($0))}),in:0...max(1,model.clock.end.timeIntervalSince(model.clock.start))).accessibilityLabel("Replay time")
            if model.store.session?.isQualifying == true {
                Menu(model.qualifying.phase.map{model.qualifyingPhaseLabel($0)} ?? L10n.text("Qualifying")) {
                    ForEach(model.qualifyingTimeline.phases) {phase in Button(model.qualifyingPhaseLabel(phase.id)){model.seek(phase.start)}}
                }.accessibilityIdentifier("qualifyingPhaseSelector")
            } else { Menu(model.store.raceStart.hasStarted ? L10n.text("Lap \(max(1,model.store.lap))"):replayPhaseLabel) {
                if model.clock.start < model.replayOpeningTime {Button(L10n.text("Pre-race")){model.seek(model.clock.start)};Button(L10n.text("Before start")){model.seek(max(model.clock.start,model.replayOpeningTime.addingTimeInterval(-4)))}}
                ForEach(1...(model.store.session?.totalLaps ?? 100),id:\.self) { n in Button("Lap \(n)") { Task { await model.seekLap(n) } } } }.fixedSize().accessibilityIdentifier("lapSelector") }
        }.font(.system(size:11,weight:.medium)).controlSize(.small).padding(6).cardSurface().disabled(!model.loading.isEmpty)
    }
    private func front(_ layout: CardLayout) -> some View {
        HStack(alignment:.top,spacing:8) {
            VStack(spacing:8) {
                OperationalMap(store:model.store,textSize:layout.text,onBackgroundTap:{ model.dismissFocus() },reference:model.referenceOverride.flatMap{model.trackRepository.load(eventKey:$0)} ?? model.store.session.flatMap{model.trackRepository.resolve($0)},metadataRoot:model.trackRepository.root,qualifyingTiming:model.qualifying.drivers[model.store.selected ?? model.qualifyingSlots.pins.compactMap{$0}.first ?? model.qualifyingSlots.visible.compactMap{$0}.first ?? -1])
                    .frame(height:max(240,min(layout.height*(layout.compact ? 0.34:0.4),layout.height-(layout.tyreColumns==11 ? 420:464)-layout.summaryHeight))).cardSurface()
                ZStack {
                    if model.store.session?.isQualifying == true {
                        QualifyingDashboard(model:model,layout:layout)
                    } else if let id=model.store.selected,let driver=model.store.drivers[id] {
                        DriverFocusView(model:model,driver:driver,layout:layout)
                            .transition(.asymmetric(insertion:.opacity,removal:.move(edge:.bottom).combined(with:.opacity)))
                    } else {
                        VStack(spacing:8) {
                            TyresView(model:model,layout:layout)
                            summary(layout)
                            FeedView(events:model.store.events,language:model.language,fontSize:layout.text).frame(maxHeight:.infinity)
                        }.transition(.opacity)
                    }
                }.animation(.easeOut(duration:reduceMotion ? 0.12 : 0.3),value:model.store.selected)
            }.frame(maxWidth:.infinity)
            Group {if model.store.session?.isQualifying == true {QualifyingLeaderboard(model:model)} else {LeaderboardView(model:model,layout:layout)}}.frame(width:(layout.width-layout.padding*2)*(layout.compact ? 0.28 : 0.26)).cardSurface()
        }
    }
    private func summary(_ layout: CardLayout) -> some View {
        let season=Calendar.current.component(.year,from:model.store.session?.start ?? Date())
        let scale=layout.summaryScale
        let height=layout.summaryHeight
        return HStack(spacing:8) {
            RaceSummaryCard(title:"FASTEST LAP",accent:.purple,identifier:"fastestSummary",scale:scale,height:height) {
                SummaryDriverIdentity(driver:model.store.fastest.flatMap{model.store.drivers[$0.driver]},season:season,scale:scale)
                Text(model.store.fastest.map{L10n.text("Lap \($0.lap.number)")} ?? "—").font(.system(size:13*scale)).foregroundStyle(.secondary)
                Text(Timing.lap(model.store.fastest?.lap.duration)).accessibilityIdentifier("fastestSummaryValue").font(.system(size:26*scale,weight:.bold,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.8)
            }
            RaceSummaryCard(title:"LATEST PIT",accent:.cyan,identifier:"latestPitSummary",scale:scale,height:height) {
                SummaryDriverIdentity(driver:model.store.latestPit.flatMap{model.store.drivers[$0.driver]},season:season,scale:scale)
                if let pit=model.store.latestPit {
                    let timing=PitTimingPresentation(stopDuration:pit.stopDuration,laneDuration:pit.laneDuration,suspended:pit.intersects(model.store.suspensions))
                    Text(L10n.text("Lap \(pit.lap)")).font(.system(size:13*scale)).foregroundStyle(.secondary)
                    if timing.suspended {Text(L10n.text("During red-flag suspension")).font(.system(size:14*scale,weight:.semibold)).fixedSize(horizontal:false,vertical:true)}
                    Text(timing.service(model.language)).font(.system(size:(pit.stopDuration == nil ? 14:20)*scale,weight:.bold,design:.monospaced)).lineLimit(2).minimumScaleFactor(0.8).accessibilityIdentifier("latestPitStopDuration")
                        .help(timing.detail(model.language))
                    if !timing.suspended,let occupancy=timing.occupancy(model.language) {
                        Text(occupancy).font(.system(size:12*scale)).foregroundStyle(.secondary).lineLimit(2).accessibilityIdentifier("latestPitLaneDuration")
                    }
                } else {Text(L10n.text("Unavailable")).font(.system(size:14*scale)).foregroundStyle(.secondary)}
            }
            RaceSummaryCard(title:"WEATHER",accent:.secondary,identifier:"weatherSummary",scale:scale,height:height) {
                Image(systemName:model.store.weather?.rain ?? 0>0 ? "cloud.rain":"thermometer.medium").font(.system(size:32*scale)).frame(height:58*scale,alignment:.top)
                if let w=model.store.weather {
                    Text(w.rain.map{L10n.text($0>0 ? "Rain detected":"No rainfall")} ?? L10n.text("Unavailable")).font(.system(size:13*scale)).foregroundStyle(.secondary)
                    Text(w.air.map{String(format:"%.1f°C",$0)} ?? "—").font(.system(size:26*scale,weight:.bold,design:.monospaced))
                    Text(w.track.map{L10n.text(String(format:"Track %.1f°",$0))+"C"} ?? "—").font(.system(size:13*scale)).foregroundStyle(.secondary)
                }
            }
        }.frame(height:height)
    }

}
struct LeaderboardView: View {
    var model: AppModel; var layout: CardLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { g in
            let rows = model.store.leaderboard
            let separate = rows.filter{model.store.displayPosition($0)==nil}
            let firstSeparate = separate.first?.id
            let rowHeight = (g.size.height-22-(separate.isEmpty ? 0 : 20))/CGFloat(max(1,rows.count)); let season = Calendar.current.component(.year,from:model.store.session?.start ?? Date())
            VStack(spacing:0) {
                HStack { Text(model.store.raceStart.suppressGaps ? "GRID" : "POS"); Spacer(); Text(model.store.raceStart.suppressGaps ? "Tyres" : "GAP") }.font(.system(size:9,weight:.bold)).frame(height:22)
                ZStack(alignment:.topLeading) {
                    if let first=firstSeparate,let index=rows.firstIndex(where:{$0.id==first}) {
                        Text(!model.store.raceStart.hasStarted && separate.allSatisfy(\.pitStart) ? "PIT START" : "Awaiting position").font(.system(size:9,weight:.bold)).frame(maxWidth:.infinity,alignment:.leading).frame(height:20).offset(y:CGFloat(index)*rowHeight) .accessibilityIdentifier("unrankedHeading")
                    }
                    ForEach(Array(rows.enumerated()),id:\.element.id) { index,d in
                        TimelineView(.periodic(from:.now,by:0.25)) { context in
                            let delta = d.movement(at:context.date)
                            let ordinaryRail = StatusRail.resolve(driver:d,state:model.store.status(d),drsEnabled:model.store.raceControl.drsEnabled && season<2026,precision:model.precision,isRace:model.store.session?.isRace ?? true)
                            let rail = model.store.waitingForPosition(d) ? StatusRail(gap:"Awaiting position",pill:nil,replacesGap:false) : model.store.raceStart.suppressGaps && model.store.session?.isRace == true ? StatusRail(gap:d.pitStart ? "PIT START" : "GRID",pill:nil,replacesGap:false) : ordinaryRail
                            Button { model.focusDriver(d.id) } label: {
                                HStack(spacing:layout.compact ? 0 : 1) {
                                    Text(model.store.displayPosition(d).map(String.init) ?? "—").lineLimit(1).fixedSize().frame(width:layout.compact ? 16 : 21,alignment:.leading)
                                    Rectangle().fill(Color(hex:d.color)).frame(width:2)
                                    TeamIdentityBadge(season:season,teamName:d.team,teamColor:d.color,size:layout.compact ? 12 : min(22,rowHeight-2))
                                    Text(d.acronym).fontWeight(.bold).fixedSize(horizontal:true,vertical:false)
                                    Spacer(minLength:0)
                                    Text(delta == 0 ? "" : delta>0 ? "↑\(delta)" : "↓\(-delta)").font(.system(size:10,weight:.bold)).foregroundStyle(delta>0 ? Color.green : .red).frame(width:layout.compact ? 13 : 22).opacity(delta == 0 ? 0 : 1).animation(.easeOut(duration:reduceMotion ? 0.12 : 0.3),value:delta)
                                    TyreCompoundLetter(compound:.init(d.currentStint?.compound))
                                    HStack(spacing:2) {
                                        if !rail.replacesGap { Text(L10n.text(rail.gap)).font(.system(size:rail.gap == "LEADER" ? 9 : layout.compact ? (rail.pill == nil ? 11 : 9) : 14,weight:rail.gap == "LEADER" ? .bold : .semibold,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.8) }
                                        if let pill = rail.pill { StatusPill(text:pill,fontSize:layout.compact ? 8 : 10) }
                                    }.frame(width:layout.compact ? 64 : 90,alignment:.trailing)
                                }.font(.system(size:layout.compact ? 11 : 15,design:.monospaced)).foregroundStyle(.primary).padding(.horizontal,2).frame(height:rowHeight-1).background((model.store.selected == d.id ? Color.accentColor : delta>0 ? .green : delta<0 ? .red : .clear).opacity(0.12),in:RoundedRectangle(cornerRadius:4)).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("driver-\(d.id)").help((["\(d.name) · \(d.team) · \(rail.gap) \(rail.pill ?? "")"]+d.stewardItems.map{$0.text(model.language,driverName:DriverNameResolver.full(d))}).joined(separator:"\n\n"))
                        }.frame(height:rowHeight).offset(y:CGFloat(index)*rowHeight+(model.store.displayPosition(d)==nil ? 20 : 0)).zIndex(d.movement(at:Date()) == 0 ? 0 : 1)
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).animation(reduceMotion ? .easeOut(duration:0.12) : .spring(response:0.65,dampingFraction:0.88),value:rows.map(\.id))
            }
        }.padding(.horizontal,5).padding(.bottom,4).background(Color.primary.opacity(0.025))
    }
}
struct TyresView: View {
    var model: AppModel; var layout: CardLayout
    var body: some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:3),count:layout.tyreColumns),spacing:5) {
            ForEach(model.store.leaderboard) { d in
                VStack(spacing:2) {
                    Text(d.acronym).font(.system(size:layout.compact ? 11 : 13,weight:.semibold)).lineLimit(1)
                    HStack(spacing:2) { TyreCompoundBadge(compound:.init(d.currentStint?.compound));Text(d.tyreAge.map{String($0)} ?? "—").font(.system(size:layout.compact ? 10 : 12,weight:.bold,design:.monospaced)).lineLimit(1) }
                }.frame(maxWidth:.infinity).help("\(d.name) · \(L10n.text(d.currentStint?.compound ?? "UNKNOWN")) · \(L10n.text("Total usage")) \(d.tyreAge.map{String($0)} ?? "—") \(L10n.text("laps"))")
            }
        }.padding(7).cardSurface().accessibilityIdentifier("tyresBand")
    }
}
