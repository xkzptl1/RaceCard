import SwiftUI

enum MapLayer: String, CaseIterable, Identifiable {
    case referenceMap, cars, sectors, raceControl, corners, startFinish, pit, speedTrap, lightPanels, marshalPosts, drsDetection, drsActivation, overtakeDetection, overtakeActivation, straightMode, lowGrip
    var id: String {rawValue}
    var title: String {
        switch self {
        case .referenceMap:return "Official map"
        case .cars:return "Car positions"
        case .raceControl:return "Race Control sectors"
        case .sectors:return "Sector boundaries · S1 / S2 / S3"
        case .corners:return "Corner numbers"
        case .startFinish:return "Start / finish"
        case .pit:return "Pit entry / exit"
        case .speedTrap:return "Speed trap"
        case .lightPanels:return "FIA light panels"
        case .marshalPosts:return "Marshal posts"
        case .drsDetection:return "DRS Detection"
        case .drsActivation:return "DRS Activation"
        case .overtakeDetection:return "Overtake Detection"
        case .overtakeActivation:return "Overtake Activation"
        case .straightMode:return "Straight Mode"
        case .lowGrip:return "Low-Grip Straight Mode"
        }
    }
}
enum MapDensity:String,CaseIterable {case simple="Simple", detailed="Detailed"}
@MainActor @Observable final class MapLayers {
    private let defaults:UserDefaults
    var density:MapDensity {didSet {defaults.set(density.rawValue,forKey:"mapDensity")}}
    var overrides:[MapLayer:Bool]=[:]
    var enabled:Set<MapLayer> {Set(MapLayer.allCases.filter{contains($0)})}
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults;density=MapDensity(rawValue:defaults.string(forKey:"mapDensity") ?? "Simple") ?? .simple
        for layer in MapLayer.allCases {if let value=(defaults.object(forKey:"mapOverride."+layer.rawValue) ?? defaults.object(forKey:"mapLayer."+layer.rawValue)) as? Bool {overrides[layer]=value}}
    }
    func contains(_ layer:MapLayer)->Bool {
        if let override=overrides[layer] {return override}
        return density == .detailed ? layer != .referenceMap : [.cars,.sectors,.corners,.startFinish,.pit].contains(layer)
    }
    func set(_ layer:MapLayer,_ value:Bool) {overrides[layer]=value;defaults.set(value,forKey:"mapOverride."+layer.rawValue)}
}
struct MapLayersPopover: View {
    var layers: MapLayers
    var available: [MapLayer]
    var onDone:()->Void = {}
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {Text("Map layers").font(.headline);Spacer();Button("Done",action:onDone).controlSize(.small).accessibilityIdentifier("closeMapLayers")}
            Picker("Map detail",selection:Binding(get:{layers.density},set:{layers.density=$0})) {ForEach(MapDensity.allCases,id:\.self){Text(L10n.text($0.rawValue)).tag($0)}}.pickerStyle(.segmented).accessibilityIdentifier("mapDensity")
            ForEach(available){layer in Toggle(L10n.text(layer.title),isOn:Binding(get:{layers.contains(layer)},set:{layers.set(layer,$0)})).accessibilityIdentifier("layer-"+layer.rawValue)}
            Text("Safety overlays always remain visible").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width:285).accessibilityElement(children:.contain).accessibilityIdentifier("mapLayersPopover")
    }
}
