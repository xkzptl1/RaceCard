import SwiftUI

struct StintHistoryView:View {
    let driver:DriverState
    var maximumHeight:CGFloat=180
    @Environment(\.colorScheme) private var scheme
    private var rows:[StintHistoryRow] {StintHistoryRow.rows(driver)}
    private var maximum:Int {max(1,rows.map{($0.prior ?? 0)+($0.raceLaps ?? 0)}.max() ?? 1)}
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            Text(L10n.text("Tyre history")).font(.system(size:12,weight:.bold))
            if rows.isEmpty {Text(L10n.text("Unavailable")).font(.caption).foregroundStyle(.secondary)}
            ScrollView {
                VStack(spacing:7) {ForEach(rows) {row in
                    VStack(alignment:.leading,spacing:4) {
                        HStack(spacing:5) {
                            Text(row.range).monospacedDigit().frame(minWidth:54,alignment:.leading)
                            TyreCompoundBadge(compound:.init(row.compound),size:.compact)
                            Text(L10n.text(row.compound)).fontWeight(.medium).accessibilityIdentifier(row.current ? "focusedCompound":"compound-\(row.id)")
                            Spacer(minLength:2)
                            Text(L10n.text(row.current ? "Current":"Finished")).font(.system(size:9,weight:row.current ? .bold:.regular)).foregroundStyle(row.current ? Color.primary:.secondary)
                        }
                        if let laps=row.raceLaps {
                            GeometryReader {proxy in
                                let unit=proxy.size.width/CGFloat(maximum),prior=max(0,row.prior ?? 0),color=TyreCompound(row.compound).color
                                HStack(spacing:0) {
                                    Rectangle().fill(color.opacity(0.25)).frame(width:CGFloat(prior)*unit)
                                    Rectangle().fill(color).frame(width:CGFloat(laps)*unit)
                                }.frame(height:7).overlay(alignment:.leading){RoundedRectangle(cornerRadius:1).stroke(Color.primary.opacity(scheme == .light ? 0.35:0.2),lineWidth:0.6).frame(width:CGFloat(prior+laps)*unit,height:7)}
                            }.frame(height:7).accessibilityIdentifier("tyreUsageGauge")
                            HStack {Text("\(laps) "+L10n.text("laps"));if let prior=row.prior {Text(L10n.text("Prior use")+": \(prior) "+L10n.text("laps")).foregroundStyle(.secondary)}}.font(.system(size:10)).monospacedDigit()
                        } else if let prior=row.prior {Text(L10n.text("Prior use")+": \(prior) "+L10n.text("laps")).font(.caption2)}
                    }.padding(6).background(Color.primary.opacity(row.current ? 0.055:0.015),in:RoundedRectangle(cornerRadius:5)).accessibilityElement(children:.combine).accessibilityIdentifier("stint-\(row.id)")
                }}
            }.frame(height:min(maximumHeight,CGFloat(rows.count)*69))
        }.padding(8).cardSurface().accessibilityIdentifier("focusedTyres")
    }
}
