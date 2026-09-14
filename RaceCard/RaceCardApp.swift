import SwiftUI
import AppKit

@main struct RaceCardApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup(Product.name) { MainView(model:model) }.defaultSize(width:700,height:900).windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing:.appSettings) { Button(L10n.text("Settings…")) { model.settings = true }.keyboardShortcut(",") }; CommandMenu(L10n.text("Session")) { Button(L10n.text("Offline Demo")) { model.loadMock() }; Button(L10n.text("Choose Session…")) { model.picker = true }.keyboardShortcut("o"); Button(L10n.text("Play / Pause")) { model.togglePlayback() }.keyboardShortcut(.space,modifiers:[]) } }
    }
}
