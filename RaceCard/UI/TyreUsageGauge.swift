import SwiftUI

struct TyreUsageGauge:View {
    var prior:Int?;var current:Int
    private var previous:Int {max(0,prior ?? 0)}
    private var total:Int {previous+max(0,current)}
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
            GeometryReader { geometry in
                let count=max(1,min(40,total)),unit=total>0 ? Double(total)/Double(count) : 1
                HStack(spacing:2) {
                    ForEach(0..<count,id:\.self) { index in
                        let fraction=min(1,max(0,(Double(previous)-Double(index)*unit)/unit))
                        GeometryReader { cell in
                            ZStack(alignment:.leading) {
                                Rectangle().fill(total==0 ? Color.secondary.opacity(0.15) : Color.accentColor)
                                Rectangle().fill(Color.secondary.opacity(0.45)).frame(width:cell.size.width*fraction)
                            }
                        }
                    }
                }.frame(width:geometry.size.width,height:9).clipShape(RoundedRectangle(cornerRadius:2))
            }.frame(height:9)
            HStack(spacing:12) {
                if prior != nil {Label("Prior usage",systemImage:"square.lefthalf.filled").foregroundStyle(.secondary)}
                Label("Current stint",systemImage:"square.fill").foregroundStyle(Color.accentColor)
            }.font(.caption2)
            Text("Lap counts only · not remaining tyre life").font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children:.combine).accessibilityIdentifier("tyreUsageGauge")
    }
}
