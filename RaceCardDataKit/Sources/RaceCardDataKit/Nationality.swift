import Foundation

/// F1 results use sporting nationality codes, which differ from ISO country codes.
/// Nationality must never be derived from a driver's birthplace or team base.
public enum Nationality {
    private static let regions = ["GBR":"GB","NED":"NL","GER":"DE","MON":"MC","SUI":"CH","RSA":"ZA","DEN":"DK","POR":"PT","CHI":"CL","RHO":"ZW","UAE":"AE","AUS":"AU","AUT":"AT","BEL":"BE","BRA":"BR","CAN":"CA","ESP":"ES","FIN":"FI","FRA":"FR","ITA":"IT","JPN":"JP","MEX":"MX","NZL":"NZ","POL":"PL","RUS":"RU","THA":"TH","USA":"US","ARG":"AR","IND":"IN","INA":"ID","CHN":"CN","HUN":"HU","VEN":"VE","COL":"CO","SWE":"SE","IRL":"IE","MAS":"MY"]
    public static func display(_ code:String?,language:String)->String? {
        guard let code,!code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return nil}
        let normalized=code.uppercased()
        guard let region=regions[normalized] ?? (normalized.count == 2 ? normalized:nil) else{return code}
        return Locale(identifier:language).localizedString(forRegionCode:region) ?? code
    }
}
