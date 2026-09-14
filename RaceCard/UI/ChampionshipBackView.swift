import SwiftUI
import RaceCardDataKit

struct ChampionshipBackView: View {
    var model: AppModel; var layout: CardLayout
    @State private var before = false
    private var locked: Bool { model.spoilerFree && [.mock,.replay].contains(model.store.mode) && model.clock.time < model.clock.end }
    private var showBefore: Bool { before || locked }
    private var season: Int { Calendar.current.component(.year,from:model.store.session?.start ?? Date()) }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("CHAMPIONSHIP").accessibilityIdentifier("backTitle").font(.system(size:layout.compact ? 22 : 30,weight:.bold,design:.rounded))
                Spacer()
                Picker("Comparison",selection:Binding(get:{showBefore},set:{before=$0})) { Text("Current / Final").tag(false);Text("Before this GP").tag(true) }.pickerStyle(.segmented).frame(maxWidth:300).disabled(locked).accessibilityIdentifier("championshipComparison")
            }
            if locked { Label("Final standings remain hidden until replay ends",systemImage:"eye.slash").font(.callout) }
            if model.store.championship.drivers.isEmpty && model.store.championship.teams.isEmpty { ContentUnavailableView("Standings unavailable for this session",systemImage:"trophy") }
            else if layout.compact {
                VStack(spacing:12) { drivers.frame(maxHeight:.infinity); constructors.frame(maxHeight:.infinity) }
            } else {
                HStack(alignment:.top,spacing:16) { drivers.frame(maxWidth:.infinity); constructors.frame(maxWidth:.infinity) }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)

    }
    private var drivers: some View {
        VStack(alignment:.leading,spacing:8) {
            Label("Drivers Championship",systemImage:"person.2.fill").font(.system(size:layout.text+2,weight:.bold))
            ScrollView { LazyVStack(spacing:0) {
                ForEach(sorted(model.store.championship.drivers)) { e in
                    let driver = model.identities.resolve(Int(e.id) ?? 0,session:model.store.session)
                    Button {model.profile = .driver(driver,e,showBefore)} label: { HStack(spacing:10) {
                        rank(e)
                        DriverPortrait(url:driver.headshotURLs.first,season:season,name:driver.fullName,fallbackURLs:Array(driver.headshotURLs.dropFirst())).accessibilityIdentifier("headshot-\(e.id)")
                        VStack(alignment:.leading,spacing:4) {
                            Text(driver.fullName).font(.system(size:layout.text,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            HStack(spacing:5) { TeamIdentityBadge(season:season,teamName:driver.team ?? "Unknown",teamColor:driver.color,size:19);Text(driver.team ?? L10n.text("Team metadata unavailable")).font(.system(size:layout.text-1)).lineLimit(1) }
                        }
                        Spacer(minLength:6);points(e)
                    }.padding(.vertical,9).padding(.horizontal,8).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("driverProfile-"+e.id)
                    Divider()
                }
            } }.accessibilityIdentifier("driverChampionship")
        }.padding(12).cardSurface()
    }
    private var constructors: some View {
        VStack(alignment:.leading,spacing:8) {
            Label("Constructors Championship",systemImage:"trophy.fill").font(.system(size:layout.text+2,weight:.bold))
            ScrollView { LazyVStack(spacing:0) {
                ForEach(sorted(model.store.championship.teams)) { e in
                    let color = model.store.drivers.values.first(where:{$0.team==e.name})?.color ?? "888888"
                    Button {model.profile = .team(e.name,e,showBefore)} label: { HStack(spacing:8) {rank(e);TeamIdentityBadge(season:season,teamName:e.name,teamColor:color,size:30);Text(e.name).font(.system(size:layout.text,weight:.semibold)).lineLimit(2);Spacer(minLength:6);points(e)}.padding(.vertical,12).padding(.horizontal,8).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("teamProfile-"+e.id)
                    Divider()
                }
            } }.accessibilityIdentifier("constructorChampionship")
        }.padding(12).cardSurface()
    }
    private func sorted(_ entries:[ChampionshipEntry])->[ChampionshipEntry] { entries.sorted { (showBefore ? $0.rankBefore : $0.rankCurrent) < (showBefore ? $1.rankBefore : $1.rankCurrent) } }
    private func rank(_ e:ChampionshipEntry)->some View { Text(String(showBefore ? e.rankBefore : e.rankCurrent)).font(.system(size:layout.text+2,weight:.bold,design:.rounded)).frame(width:24) }
    private func points(_ e:ChampionshipEntry)->some View {
        VStack(alignment:.trailing,spacing:3) {
            HStack(spacing:5) { Text((showBefore ? e.before : e.current).formatted(.number.precision(.fractionLength(0...1)))).font(.system(size:layout.text+2,weight:.bold,design:.monospaced));if !showBefore && e.delta>0 { Text(String(format:"+%.0f",e.delta)).font(.system(size:layout.text-1,weight:.semibold)).foregroundStyle(.green) } }
            Text(L10n.text(showBefore ? "BEFORE THIS GP" : "Before: \(e.before.formatted()) · P\(e.rankBefore)")).font(.system(size:10)).foregroundStyle(.secondary)
        }.fixedSize(horizontal:true,vertical:false)
    }
}
