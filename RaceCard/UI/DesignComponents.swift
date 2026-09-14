import SwiftUI
import AppKit
import CoreText

extension Color {
    init(hex: String) { let v = UInt64(hex,radix:16) ?? 0x888888; self.init(red:Double((v>>16)&255)/255,green:Double((v>>8)&255)/255,blue:Double(v&255)/255) }
}
struct CardLayout {
    let width: CGFloat; let height: CGFloat
    var compact: Bool { width < 900 }
    var wide: Bool { width > 1300 }
    var text: CGFloat { max(14,min(19,width/75)) }
    var summaryScale:CGFloat {max(1,min(1.35,width/1100))}
    var summaryHeight:CGFloat {216*summaryScale}
    var padding: CGFloat { compact ? 10 : 18 }
    var centralHeight: CGFloat { max(360,min(height * (compact ? 0.48 : 0.57),height-(compact ? 430 : wide ? 460 : 490))) }
    var tyreColumns: Int { width>=850 ? 11:8 }
}
struct TeamAssetRegistry {
    struct Entry: Equatable { var key: String; var monogram: String; var asset: String? }
    static func resolve(season: Int, name: String) -> Entry {
        let n = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let aliases: [(String,[String],String,String)] = [
            ("mclaren",["mclaren","mclarenracing","mclarenmastercardf1team"],"MCL","team_mclaren"),
            ("redbull",["redbull","redbullracing","oracleredbullracing"],"RBR","team_red_bull_racing"),
            ("ferrari",["ferrari","scuderiaferrari","scuderiaferrarihp"],"FER","team_ferrari"),
            ("mercedes",["mercedes","mercedesamgpetronasf1team"],"MER","team_mercedes"),
            ("astonmartin",["astonmartin","astonmartinaramcof1team"],"AM","team_aston_martin"),
            ("alpine",["alpine","bwtalpinef1team"],"ALP","team_alpine"),
            ("williams",["williams","williamsracing","atlassianwilliamsf1team"],"WIL","team_williams"),
            ("haas",["haas","haasf1team","tgrhaasf1team","moneygramhaasf1team"],"HAAS","team_haas"),
            ("racingbulls",["racingbulls","rb","visacashapprb","visacashappracingbullsf1team"],"RB","team_racing_bulls"),
            ("audi",["audi","audirevolutf1team"],"AUD","team_audi"),
            ("cadillac",["cadillac","cadillacf1team","cadillacformula1team"],"CAD","team_cadillac")]
        if let e = aliases.first(where:{ $0.1.contains(n) }) {
            let firstSeason = ["audi","cadillac"].contains(e.0) ? 2026 : 2025
            return .init(key:e.0,monogram:e.2,asset:(firstSeason...2026).contains(season) ? e.3 : nil)
        }
        let words = name.split(whereSeparator:{ !$0.isLetter && !$0.isNumber }); let mono = words.count > 1 ? words.prefix(3).compactMap(\.first).map(String.init).joined() : String(name.prefix(3))
        return .init(key:n,monogram:mono.isEmpty ? "?" : mono.uppercased(),asset:nil)
    }
}
struct TeamIdentityBadge: View {
    var season: Int; var teamName: String; var teamColor: String; var size: CGFloat = 18
    var body: some View {
        let entry = TeamAssetRegistry.resolve(season:season,name:teamName)
        ZStack {
            RoundedRectangle(cornerRadius:3).fill(Color.primary.opacity(0.035))
            if let image=TeamBrandLibrary.shared.image(season:season,team:teamName) {Image(nsImage:image).renderingMode(image.isTemplate ? .template:.original).resizable().scaledToFit().padding(1)}
            else if let asset = entry.asset,let source=NSImage(named:asset) { let image=TeamBrandLibrary.opticallyNormalized(source);Image(nsImage:image).renderingMode(image.isTemplate ? .template:.original).resizable().scaledToFit().padding(1) }
            else { Text(entry.monogram).font(.system(size:max(6,size*0.35),weight:.bold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7) }
        }.frame(width:size,height:size).overlay(alignment:.bottom) { Rectangle().fill(Color(hex:teamColor)).frame(height:2) }.clipShape(RoundedRectangle(cornerRadius:3)).accessibilityLabel(teamName).help(teamName)
    }
}
enum TyreCompound: String, CaseIterable {
    case soft = "SOFT", medium = "MEDIUM", hard = "HARD", intermediate = "INTERMEDIATE", wet = "WET", unknown = "UNKNOWN"
    init(_ raw: String?) { self = Self(rawValue:raw?.uppercased() ?? "") ?? .unknown }
    var letter: String { self == .unknown ? "?" : String(rawValue.prefix(1)) }
    var color: Color { switch self { case .soft:return .red; case .medium:return .yellow; case .hard:return .white; case .intermediate:return .green; case .wet:return .blue; case .unknown:return .gray } }
}
// Center the actual glyph outline, independently of font side bearings and baseline metrics.
struct CompoundGlyph: Shape {
    var letter: String
    var fontSize: CGFloat
    func path(in rect: CGRect) -> Path {
        let font = NSFont.monospacedSystemFont(ofSize:fontSize,weight:.black) as CTFont
        var character = letter.utf16.first ?? 63
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font,&character,&glyph,1),
              let outline = CTFontCreatePathForGlyph(font,glyph,nil) else { return Path() }
        let bounds = outline.boundingBoxOfPath
        let transform = CGAffineTransform(a:1,b:0,c:0,d:-1,
            tx:rect.midX-bounds.midX,ty:rect.midY+bounds.midY)
        return Path(outline).applying(transform)
    }
}
struct TyreCompoundLetter: View {
    var compound: TyreCompound
    var body: some View {
        ZStack(alignment:.center) {
            // A fine outline keeps white H and yellow M legible on Light backgrounds.
            CompoundGlyph(letter:compound.letter,fontSize:12).stroke(Color.black.opacity(0.8),lineWidth:0.7)
            CompoundGlyph(letter:compound.letter,fontSize:12).fill(compound.color)
        }.frame(width:16,height:16,alignment:.center).fixedSize()
            .accessibilityLabel(L10n.text(compound.rawValue)).help(L10n.text(compound.rawValue))
    }
}
struct TyreCompoundBadge: View {
    enum Size { case compact, regular; var points: CGFloat { self == .compact ? 16 : 23 } }
    var compound: TyreCompound; var size: Size = .regular
    var body: some View {
        ZStack(alignment:.center) {
            Circle().fill(Color(white:0.12))
            Circle().stroke(compound.color,lineWidth:size == .compact ? 2 : 3).padding(2)
            CompoundGlyph(letter:compound.letter,fontSize:size == .compact ? 9 : 12)
                .fill(.white).frame(width:size.points,height:size.points,alignment:.center)
        }.frame(width:size.points,height:size.points,alignment:.center).fixedSize()
            .overlay(Circle().stroke(Color.primary.opacity(0.55),lineWidth:0.8))
            .accessibilityLabel(L10n.text(compound.rawValue)).help(L10n.text(compound.rawValue))
    }
}
struct StatusPill: View {
    var text: String; var fontSize: CGFloat = 9
    var body: some View { Text(text).font(.system(size:fontSize,weight:.bold,design:.monospaced)).foregroundStyle(Color.primary).padding(.horizontal,3).padding(.vertical,1).background(tint.opacity(0.23),in:RoundedRectangle(cornerRadius:3)).overlay(RoundedRectangle(cornerRadius:3).stroke(tint.opacity(0.7),lineWidth:0.5)) }
    var tint: Color { ["STOP","OUT","DNF","DNS","DSQ"].contains(text) ? .red : text == "DRS" ? .green : text == "PIT" ? .blue : .orange }
}
extension View {
    func cardSurface() -> some View { background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(Color.primary.opacity(0.10),lineWidth:1).allowsHitTesting(false)) }
}
