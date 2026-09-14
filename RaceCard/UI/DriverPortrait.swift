import SwiftUI

struct DriverPortrait: View {
    var url:String?;var season:Int;var name:String;var width:CGFloat=38;var height:CGFloat=44
    var fallbackURLs:[String]=[]
    @State private var data:Data?
    private var canonicalIdentity:String {
        let acronym=DriverNameResolver.japaneseFullNames.first(where:{$0.value == name})?.key
        return DriverRegistry.stableID(acronym.flatMap{DriverNameResolver.fullNames[$0]} ?? name)
    }
    private var sources:[String] {
        var seen=Set<String>()
        return ([url].compactMap{$0}+fallbackURLs+DriverPortraitSources.urls(identity:canonicalIdentity,season:season)).filter{seen.insert($0).inserted}
    }
    var body:some View {
        ZStack {
            RoundedRectangle(cornerRadius:6).fill(.secondary.opacity(0.12))
            if let data,let image=NSImage(data:data) {Image(nsImage:image).resizable().scaledToFill().frame(width:width,height:height,alignment:.top).clipped()}
            else {Image(systemName:"person.crop.circle.fill").resizable().scaledToFit().padding(4).foregroundStyle(.secondary)}
        }.frame(width:width,height:height).clipShape(RoundedRectangle(cornerRadius:6))
            .accessibilityLabel(name).accessibilityValue(data == nil ? L10n.text("Portrait unavailable") : L10n.text("Portrait loaded"))
            .task(id:"\(season):\(url ?? ""):\(fallbackURLs.joined())") {
                data=await DriverImageRepository.shared.cachedImageData(season:season,identity:canonicalIdentity)
                let loaded=await DriverImageRepository.shared.imageData(urls:sources,season:season,identity:canonicalIdentity)
                if !Task.isCancelled {data=loaded}
            }
    }
}

@MainActor enum DriverPortraitSources {
    static var records:[DriverSnapshot]=[]
    static func urls(identity:String,season:Int)->[String] {
        let matches=records.filter{$0.identityID==identity && $0.season<=season && $0.headshotURL != nil}
        let newest=matches.map(\.season).max()
        return matches.filter{$0.season==newest}.sorted{$0.date>$1.date}.compactMap(\.headshotURL)
    }
}
