import Foundation
import Observation

@MainActor @Observable final class Localization {
    static let shared = Localization()
    var language: String { didSet { UserDefaults.standard.set(language,forKey:"language") } }
    private init() { language = UserDefaults.standard.string(forKey:"language") == "en" ? "en" : "ja" }
}
enum L10n {
    @MainActor static func text(_ source: String) -> String { text(source,language:Localization.shared.language) }
    static func text(_ source: String, language: String) -> String {
        guard language == "ja", let path = Bundle.main.path(forResource:"ja",ofType:"lproj"), let bundle = Bundle(path:path) else { return source }
        let direct = bundle.localizedString(forKey:source,value:source,table:nil)
        if direct != source { return direct }
        // Only application-generated templates are translated; provider messages stay verbatim.
        for template in ["Before: %@ · P%@","Lap %@","LAST · L%@","Finding %@ sessions…","Fetching %@…","Source sector %@ · %@","Stop %@s","Lane %@s","Air %@°","Track %@°","DATA DELAYED · %@s","LIVE · +%@s","LIVE · %@s","Waiting for data · %@s",", used at start (%@L)","OpenF1 returned HTTP %@. Last known data is retained. Retry when the service is available."] {
            let pattern = "^" + template.components(separatedBy:"%@").map { NSRegularExpression.escapedPattern(for:$0) }.joined(separator:"(.+?)") + "$"
            guard let regex = try? NSRegularExpression(pattern:pattern), let match = regex.firstMatch(in:source,range:NSRange(source.startIndex...,in:source)) else { continue }
            let args = (1..<match.numberOfRanges).compactMap { Range(match.range(at:$0),in:source).map { text(String(source[$0]),language:language) } }
            return String(format:bundle.localizedString(forKey:template,value:template,table:nil),arguments:args)
        }
        return source
    }
}

extension L10n {
    @MainActor static func zone(_ value:String)->String {
        guard Localization.shared.language=="ja" else{return value}
        if let c=JapaneseRaceText.capture(#"^(\d+)m (after|before) (T\d+)(.*)$"#,value) {
            return c[2]+"の"+c[0]+"m"+(c[1]=="after" ? "後" : "手前")+c[3].replacingOccurrences(of:"Pit Exit",with:"ピット出口")
        }
        if let c=JapaneseRaceText.capture(#"^(Entry|Exit|Apex) (T\d+)$"#,value) {return c[1]+(c[0]=="Entry" ? "入口" : c[0]=="Exit" ? "出口" : "頂点")}
        var result=value
        for (from,to) in [("Pit Exit","ピット出口"),("Entry","入口"),("Exit","出口"),("exit","出口"),("Apex","頂点"),("after","後"),("before","手前")] {result=result.replacingOccurrences(of:from,with:to)}
        return result
    }
}

extension L10n {
    @MainActor static func failure(_ message:String)->String {
        let translated=text(message)
        guard Localization.shared.language=="ja",translated==message,
              !message.unicodeScalars.contains(where:{$0.value>=0x3000 && $0.value<=0x9fff}) else{return translated}
        return text("Operation failed. Please retry.")
    }
}
