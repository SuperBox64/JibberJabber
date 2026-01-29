import SwiftUI
import JJLib

@main
struct BattleScriptApp: App {
    init() {
        JJEnv.basePath = Bundle.main.resourcePath! + "/common"
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}
