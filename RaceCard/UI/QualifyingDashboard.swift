import SwiftUI

extension TimingMerit {
    func color(_ scheme:ColorScheme)->Color {switch self {case .sessionBest:return scheme == .light ? Color(hex:"8123B3"):.purple;case .personalBest:return scheme == .light ? Color(hex:"007B39"):.green;case .neutral:return .primary}}
}
struct QualifyingDashboard:View {
    var model:AppModel;var layout:CardLayout
    var body:some View {
        VStack(spacing:8) {
            HStack {
                Text(model.qualifying.phase.map{model.qualifyingPhaseLabel($0)} ?? L10n.text("Qualifying")).font(.headline)
                Spacer()
                if let w=model.store.weather {Text([w.air.map{String(format:"%.1f°C",$0)},w.rain.map{L10n.text($0>0 ? "Rain detected":"No rainfall")}].compactMap{$0}.joined(separator:" · ")).font(.system(size:13))}
            }
            if let id=model.store.selected,let driver=model.store.drivers[id] {
                HStack {Text(DriverNameResolver.full(driver)).font(.headline);Spacer();Button {model.dismissFocus()} label:{Image(systemName:"xmark")}.accessibilityIdentifier("closeFocus")}
                ScrollView {
                    VStack(spacing:8) {
                        QualifyingTimingCard(model:model,driver:driver,slot:nil)
                        DriverFocusView(model:model,driver:driver,layout:layout,compactTelemetry:true).telemetryStrip
                    }
                }.frame(height:min(400,max(260,layout.height*0.40)))
                FeedView(events:model.focusedEvents,language:model.language,fontSize:layout.text,qualifying:true).frame(maxHeight:.infinity)
            } else {
                HStack(alignment:.top,spacing:8) {
                    ForEach(0..<3,id:\.self) {slot in
                        if let id=model.qualifyingSlots.visible[slot],let driver=model.store.drivers[id] {
                            QualifyingTimingCard(model:model,driver:driver,slot:slot)
                        } else {Text(L10n.text("No Time")).frame(maxWidth:.infinity)}
                    }
                }
                FeedView(events:model.store.events.filter{!["PIT","TYRE CHANGE"].contains($0.category)},language:model.language,fontSize:layout.text,qualifying:true).frame(maxHeight:.infinity)
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("qualifyingDashboard")
    }
}
struct QualifyingTimingCard:View {
    @Environment(\.colorScheme) private var colorScheme
    var model:AppModel;var driver:DriverState;var slot:Int?
    var timing:QualifyingDriverTiming {model.qualifying.drivers[driver.id] ?? .init(driver:driver.id)}
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(spacing:4) {
                TeamIdentityBadge(season:Calendar.current.component(.year,from:model.store.session?.start ?? Date()),teamName:driver.team,teamColor:driver.color,size:22)
                Button(driver.acronym){model.focusDriver(driver.id)}.buttonStyle(.plain).font(.system(size:15,weight:.bold))
                TyreCompoundLetter(compound:.init(driver.currentStint?.compound))
                Spacer(minLength:0)
                if let slot {
                    Menu {
                        Button(L10n.text("Automatic")){model.pinQualifying(nil,slot:slot)}
                        ForEach(model.store.drivers.values.sorted{$0.acronym<$1.acronym}) {d in Button(d.acronym){model.pinQualifying(d.id,slot:slot)}}
                    } label:{Image(systemName:model.qualifyingSlots.pins[slot] == nil ? "pin":"pin.fill")}
                        .menuStyle(.borderlessButton).fixedSize().accessibilityIdentifier("qualifyingPin-\(slot)")
                }
            }
            HStack {Text(L10n.text(timing.state)).foregroundStyle(timing.state=="Lap Deleted" ? .red:.secondary);Spacer(minLength:0);Text(timing.current.map{"L\($0.number)"} ?? "—")}.font(.system(size:12,weight:.semibold)).lineLimit(1)
            Text(L10n.text(timing.state=="Completed Lap" || timing.state=="Lap Deleted" ? "Lap time":"Current Lap")).font(.system(size:11)).foregroundStyle(.secondary)
            Text(Timing.lap(timing.elapsed)).font(.system(size:30,weight:.bold,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.65).accessibilityIdentifier("qualifyingTime-\(driver.id)")
            if slot == nil {
                HStack {
                    ForEach(0..<3,id:\.self) {i in
                        VStack(spacing:5) {
                            Text("S\(i+1)").font(.system(size:13,weight:.semibold))
                            Text(timing.sectors[i].map{String(format:"%.3f",$0)} ?? "…").font(.system(size:22,weight:.semibold,design:.monospaced)).foregroundStyle(timing.merits[i].color(colorScheme))
                        }.frame(maxWidth:.infinity).accessibilityElement(children:.combine).accessibilityIdentifier("qualifyingSector-\(driver.id)-\(i+1)")
                    }
                }
            } else {
            ForEach(0..<3,id:\.self) {i in
                HStack {
                    Text("S\(i+1)").font(.system(size:13,weight:.semibold));Spacer(minLength:3)
                    Text(timing.sectors[i].map{String(format:"%.3f",$0)} ?? "…").font(.system(size:18,weight:.semibold,design:.monospaced)).foregroundStyle(timing.merits[i].color(colorScheme))
                }.accessibilityElement(children:.combine).accessibilityIdentifier("qualifyingSector-\(driver.id)-\(i+1)")
                    .help(L10n.text(timing.merits[i] == .sessionBest ? "Session Best":timing.merits[i] == .personalBest ? "Personal Best":"Sector time"))
            }
            }
            HStack {Text(L10n.text("Against best")).font(.system(size:11));Spacer();Text(timing.delta.map{String(format:"%+.3f",$0)} ?? "—").font(.system(size:14,weight:.semibold,design:.monospaced))}.foregroundStyle(.secondary).frame(height:18)
            Divider()
            HStack {Text(L10n.text("Best Lap")).font(.system(size:11));Spacer(minLength:2);Text(Timing.lap(timing.best)).font(.system(size:14,weight:.bold,design:.monospaced))}.lineLimit(1).minimumScaleFactor(0.7)
            if slot == nil {
                HStack {ForEach(timing.phaseBests.keys.sorted(),id:\.self) {p in VStack {Text(model.qualifyingPhaseLabel(p));Text(Timing.lap(timing.phaseBests[p])).monospacedDigit()}.frame(maxWidth:.infinity)}}.font(.system(size:14))
            }
        }.padding(10).frame(maxWidth:.infinity,alignment:.topLeading).cardSurface()
            .overlay(alignment:.leading){RoundedRectangle(cornerRadius:2).fill(Color(hex:driver.color)).frame(width:3).padding(.vertical,10)}
            .accessibilityElement(children:.contain).accessibilityIdentifier("qualifyingCard-\(driver.id)")
    }
}
struct QualifyingLeaderboard:View {
    var model:AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        GeometryReader {g in
            let ids=model.qualifying.order
            let cut=model.qualifying.cut
            let h=max(29,(g.size.height-26-(cut == nil ? 0:14))/CGFloat(max(1,ids.count)))
            let season=Calendar.current.component(.year,from:model.store.session?.start ?? Date())
            VStack(spacing:0) {
                HStack {Text("POS");Spacer();Text(L10n.text("Best Lap")+" / "+L10n.text("GAP"))}.font(.system(size:10,weight:.bold)).frame(height:26)
                ScrollView {
                    ZStack(alignment:.topLeading) {
                        if let cut {
                            HStack(spacing:3){Rectangle().fill(.orange).frame(height:1);Text(L10n.text("Elimination line")).font(.system(size:10,weight:.bold)).fixedSize().foregroundStyle(.orange);Rectangle().fill(.orange).frame(height:1)}.frame(height:14).offset(y:CGFloat(cut)*h).accessibilityIdentifier("qualifyingCutLine")
                        }
                        ForEach(Array(ids.enumerated()),id:\.element) {index,id in
                            if let d=model.store.drivers[id],let t=model.qualifying.drivers[id] {
                                TimelineView(.periodic(from:.now,by:0.25)) {context in
                                    let delta=model.qualifyingRankMotion.movement(id,at:context.date)
                                    Button{model.focusDriver(id)} label:{
                                        HStack(spacing:3) {
                                            Text("\(index+1)").frame(width:19,alignment:.leading)
                                            Rectangle().fill(Color(hex:d.color)).frame(width:2)
                                            VStack(alignment:.leading,spacing:2) {
                                                HStack(spacing:3){
                                                    TeamIdentityBadge(season:season,teamName:d.team,teamColor:d.color,size:16)
                                                    Text(d.acronym).fontWeight(.bold).fixedSize()
                                                    TyreCompoundLetter(compound:.init(d.currentStint?.compound))
                                                }
                                                HStack(spacing:3) {
                                                    Text(delta == 0 ? "" : delta>0 ? "↑\(delta)":"↓\(-delta)").fontWeight(.bold).foregroundStyle(delta>0 ? Color.green:.red).frame(width:20,alignment:.leading)
                                                    Text(t.eliminated ? L10n.text("Eliminated"):t.state=="Push Lap" ? L10n.text("Push Lap"):t.best == nil && t.rankPhase>0 ? model.qualifyingPhaseLabel(t.rankPhase):" ").foregroundStyle(.secondary)
                                                }.font(.system(size:10)).lineLimit(1)
                                            }
                                            Spacer(minLength:0)
                                            VStack(alignment:.trailing,spacing:3) {
                                                Text(Timing.lap(t.best ?? t.phaseBests[t.rankPhase])).font(.system(size:14,weight:.bold,design:.monospaced)).fixedSize()
                                                Text(gap(t)).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
                                            }
                                        }.foregroundStyle(.primary).padding(.horizontal,3).frame(height:h-1)
                                            .background((model.store.selected==id ? Color.accentColor:delta>0 ? .green:delta<0 ? .red:.clear).opacity(0.12),in:RoundedRectangle(cornerRadius:4))
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("qualifyingDriver-\(id)")
                                }.frame(height:h).offset(y:CGFloat(index)*h+(cut.map{index >= $0} == true ? 14:0))
                                    .zIndex(model.qualifyingRankMotion.movement(id,at:Date()) == 0 ? 0:1)
                            }
                        }
                    }.frame(height:CGFloat(ids.count)*h+(cut == nil ? 0:14),alignment:.topLeading)
                        .animation(model.qualifyingAnimateRanks ? (reduceMotion ? .easeOut(duration:0.12):.spring(response:0.65,dampingFraction:0.88)):nil,value:ids)
                }
            }
        }.padding(.horizontal,5).accessibilityElement(children:.contain).accessibilityIdentifier("qualifyingLeaderboard")
    }
    func gap(_ t:QualifyingDriverTiming)->String {
        guard let best=t.best,let lead=model.qualifying.leader else{return "—"}
        return best==lead ? "—":String(format:"+%.3f",best-lead)
    }
}
