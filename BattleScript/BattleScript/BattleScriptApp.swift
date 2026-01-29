import SwiftUI
import JJLib

@main
struct BattleScriptApp: App {
    init() {
        UserDefaults.standard.register(defaults: ["showLineNumbers": true])
        JJEnv.basePath = Bundle.main.resourcePath! + "/common"
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}
