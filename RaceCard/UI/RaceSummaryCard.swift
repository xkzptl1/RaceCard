import SwiftUI

/// One layout contract for all three race summaries.
struct RaceSummaryCard<Content:View>:View {
    let title:String;let accent:Color;let identifier:String
    var scale:CGFloat=1
    var height:CGFloat=216
    @ViewBuilder var content:Content
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(L10n.text(title)).font(.system(size:13*scale,weight:.bold)).foregroundStyle(accent).lineLimit(1)
            content
            Spacer(minLength:0)
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .padding(12).frame(height:height,alignment:.topLeading).background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(Color.primary.opacity(0.08),lineWidth:1))
            .overlay(alignment:.leading){Capsule().fill(accent).frame(width:3).padding(.vertical,10)}
            .accessibilityElement(children:.contain).accessibilityIdentifier(identifier)
    }
}
struct SummaryDriverIdentity:View {
    let driver:DriverState?;let season:Int
    var scale:CGFloat=1
    var body:some View {
        HStack(alignment:.top,spacing:5) {
            if let driver {
                DriverPortrait(url:driver.headshotURL,season:season,name:DriverNameResolver.full(driver),width:34*scale,height:40*scale)
                VStack(alignment:.leading,spacing:3) {
                    Text(DriverNameResolver.full(driver)).font(.system(size:14*scale,weight:.semibold)).lineLimit(2).fixedSize(horizontal:false,vertical:true)
                    TeamIdentityBadge(season:season,teamName:driver.team,teamColor:driver.color,size:18*scale)
                }
            } else {Text(L10n.text("Unavailable")).font(.system(size:14*scale)).foregroundStyle(.secondary)}
        }.frame(height:58*scale,alignment:.top)
    }
}
