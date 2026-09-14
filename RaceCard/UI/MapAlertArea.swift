import SwiftUI

struct MapAlertArea:View {
    var notice:MapNotice;var store:RaceStateStore;var textSize:CGFloat
    private var bright:Bool {["YELLOW FLAG","DOUBLE YELLOW","SAFETY CAR","VSC","PENALTY","INVESTIGATION","FORMATION LAP","GRID FORMING"].contains(notice.category)}
    private var tint:Color {
        switch notice.category {
        case "FORMATION LAP","GRID FORMING":return Color(red:0.42,green:0.57,blue:0.72)
        case "SAFETY CAR","DOUBLE YELLOW","VSC":return .orange
        case "RED FLAG","SUSPENDED","CAR STOPPED","RETIRED","MECHANICAL":return .red
        default:return EventColor.color(notice.category)
        }
    }
    var body:some View {
        HStack(spacing:9) {
            if ["SAFETY CAR","VSC"].contains(notice.category) {
                Text(notice.category == "SAFETY CAR" ? "SC":"VSC").font(.system(size:textSize+4,weight:.heavy))
            } else {Image(systemName:EventColor.symbol(notice.category)).font(.system(size:textSize+4,weight:.bold))}
            Text(notice.event?.localizedText(Localization.shared.language) ?? RaceEventFacts(fields:[:],names:[],japaneseNames:[]).text(category:notice.category,raw:nil,language:Localization.shared.language)).font(.system(size:textSize,weight:.bold)).fixedSize(horizontal:false,vertical:true)
            if notice.category=="FASTEST LAP",let id=notice.driver,let d=store.drivers[id] {
                DriverPortrait(url:d.headshotURL,season:Calendar.current.component(.year,from:store.session?.start ?? Date()),name:DriverNameResolver.full(d),width:30,height:34)
            }
        }.foregroundStyle(.primary).padding(11)
            .background {
                RoundedRectangle(cornerRadius:9).fill(tint.opacity(0.30))
            }.overlay(RoundedRectangle(cornerRadius:9).stroke(tint.opacity(0.55),lineWidth:1))
            .accessibilityElement(children:.combine).accessibilityIdentifier("mapNotice")
    }
}
