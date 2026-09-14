import SwiftUI
import RaceCardDataKit

enum ProfileRoute:Identifiable {
    case driver(ResolvedDriver,ChampionshipEntry,Bool)
    case team(String,ChampionshipEntry,Bool)
    var id:String {switch self {case .driver(let driver,_,_):return "driver-"+driver.id;case .team(let team,_,_):return "team-"+team}}
}
struct ProfileView:View {
    var route:ProfileRoute
    var model:AppModel
    var close:()->Void
    private var season:Int {Calendar.current.component(.year,from:model.store.session?.start ?? Date())}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Button(action:close) {Label("Back to championship",systemImage:"chevron.left")}.accessibilityIdentifier("closeProfile")
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    switch route {
                    case .driver(let driver,let standing,let before):
                        HStack(alignment:.top,spacing:24) {
                            DriverPortrait(url:driver.headshotURLs.first,season:season,name:driver.fullName,width:160,height:190,fallbackURLs:Array(driver.headshotURLs.dropFirst()))
                            VStack(alignment:.leading,spacing:10) {
                                Text(model.language == "ja" ? DriverNameResolver.japaneseFullNames[driver.acronym] ?? driver.fullName:driver.fullName).font(.largeTitle.bold()).textSelection(.enabled)
                                Text("\(driver.number) · \(Nationality.display(driver.nationality,language:model.language) ?? L10n.text("Nationality unavailable"))").font(.title3).accessibilityIdentifier("profileNationality").accessibilityLabel(Nationality.display(driver.nationality,language:model.language) ?? L10n.text("Nationality unavailable"))
                                if let team=driver.team {HStack {TeamIdentityBadge(season:season,teamName:team,teamColor:driver.color,size:36);Text(team).font(.title2)}}
                                standingSummary(standing,before:before)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                        if let metadata=driver.metadata {
                            facts(metadata.facts)
                            assignments(metadata.history+model.identities.registry.observedHistory(identity:driver.id),title:"Team history")
                            titleSeasons(metadata.championships)
                            championships(metadata.championships)
                            sources(metadata.sources)
                        } else {Text("Verified career metadata unavailable").foregroundStyle(.secondary)}
                        if let diagnostic=driver.diagnostic {Text(diagnostic).font(.caption).foregroundStyle(.secondary)}
                    case .team(let name,let standing,let before):
                        HStack(spacing:24) {
                            TeamIdentityBadge(season:season,teamName:name,teamColor:"888888",size:150)
                            VStack(alignment:.leading,spacing:10) {Text(name).font(.largeTitle.bold());standingSummary(standing,before:before)}
                        }
                        let members=model.store.drivers.values.filter{$0.team==name}.sorted{$0.name<$1.name}
                        if !members.isEmpty {VStack(alignment:.leading,spacing:8) {Text("Session drivers").font(.title2.bold());ForEach(members) {driver in Text(DriverNameResolver.full(driver)).font(.headline)}}}
                        if let metadata=model.identities.teams.resolve(name) {
                            facts(metadata.facts)
                            if !metadata.aliases.isEmpty {Text(metadata.aliases.joined(separator:" · ")).foregroundStyle(.secondary)}
                            assignments(metadata.history,title:"Team history")
                            assignments(metadata.staff,title:"Leadership and staff")
                            if let titles=metadata.driverChampionships,!titles.isEmpty {VStack(alignment:.leading,spacing:6) {Text("Drivers’ titles with this team").font(.title2.bold());Text(titles.sorted{$0.season<$1.season}.map{String($0.season)}.joined(separator:" · "))}}
                            titleSeasons(metadata.championships)
                            championships(metadata.championships)
                            sources(metadata.sources)
                        } else {Text("Verified team history unavailable").foregroundStyle(.secondary)}
                    }
                }.padding(20).frame(maxWidth:1000,alignment:.leading).frame(maxWidth:.infinity)
            }
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor)).accessibilityElement(children:.contain).accessibilityIdentifier("profilePage")
    }
    private func standingSummary(_ entry:ChampionshipEntry,before:Bool)->some View {
        Text("P\(before ? entry.rankBefore:entry.rankCurrent) · \((before ? entry.before:entry.current).formatted()) \(L10n.text("points")) · \(String(season))").font(.title3.monospacedDigit())
    }
    private func facts(_ values:[String:SourcedValue])->some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:210),alignment:.leading)],alignment:.leading,spacing:16) {
            ForEach(values.keys.sorted(),id:\.self) {key in
                if let fact=values[key] {VStack(alignment:.leading,spacing:5) {Text(L10n.text(key)).font(.caption).foregroundStyle(.secondary);Text(key == "Nationality" ? Nationality.display(fact.value,language:model.language) ?? fact.value:fact.value).font(.title3.bold()).textSelection(.enabled)}.frame(maxWidth:.infinity,alignment:.leading).padding(12).cardSurface()}
            }
        }
    }
    @ViewBuilder private func assignments(_ values:[TemporalAssignment],title:String)->some View {
        if !values.isEmpty {VStack(alignment:.leading,spacing:10) {Text(L10n.text(title)).font(.title2.bold());ForEach(values.sorted{$0.validFrom>$1.validFrom}) {assignment in
            VStack(alignment:.leading,spacing:4) {Text("\(assignment.personID) · \(assignment.teamID) · \(L10n.text(assignment.role))").font(.headline);Text(period(assignment)).foregroundStyle(.secondary);sources(assignment.sources)}
        }}}
    }
    @ViewBuilder private func titleSeasons(_ seasons:[ChampionshipSeason])->some View {
        let wins=seasons.filter{$0.position == 1}.sorted{$0.season<$1.season}
        if !wins.isEmpty {VStack(alignment:.leading,spacing:6) {Text("Championship seasons").font(.title2.bold());Text(wins.map{String($0.season)}.joined(separator:" · ")).font(.headline).textSelection(.enabled)}}
    }
    @ViewBuilder private func championships(_ values:[ChampionshipSeason])->some View {
        if !values.isEmpty {VStack(alignment:.leading,spacing:8) {Text("Season results").font(.title2.bold());ForEach(Array(values.enumerated()),id:\.offset) {_,value in
            HStack {Text(String(value.season));if let position=value.position {Text("P\(position)")};if let points=value.points {Text(points.formatted()+" "+L10n.text("points"))};if let event=value.clinchingEvent {Text(event)};if let date=value.clinchingDate {Text(date)}}
        }}}
    }
    private func period(_ assignment:TemporalAssignment)->String {
        if assignment.role == "Season classification team" {return assignment.validFrom+" · "+L10n.text("Season affiliation")}
        if assignment.sessionKey != nil {return L10n.text("Session entry")+" · "+String(assignment.validFrom.prefix(10))}
        if assignment.sources.first?.verifiedAt == assignment.validFrom {return L10n.text("Verified on")+" "+assignment.validFrom}
        return assignment.validFrom+" – "+(assignment.validTo ?? L10n.text("Present"))
    }
    private func sources(_ values:[SourceEvidence])->some View {
        VStack(alignment:.leading,spacing:4) {ForEach(Array(values.enumerated()),id:\.offset) {_,source in if let url=URL(string:source.url) {Link(source.publisher+" · "+source.verifiedAt,destination:url).font(.caption)}}}
    }
}
