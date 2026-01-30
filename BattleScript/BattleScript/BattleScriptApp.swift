import SwiftUI
import JJLib

@main
struct BattleScriptApp: App {
    init() {
        UserDefaults.standard.register(defaults: ["showLineNumbers": true])
        if let resourcePath = Bundle.main.resourcePath {
            JJEnv.basePath = resourcePath + "/common"
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}
