import SwiftUI
import JJLib

@main
struct BattleScriptApp: App {
    @AppStorage("showLineNumbers") private var showLineNumbers = true

    init() {
        UserDefaults.standard.register(defaults: ["showLineNumbers": true])
        JJEnv.basePath = Bundle.main.resourcePath! + "/common"
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("Editor") {
                Toggle("Show Line Numbers", isOn: $showLineNumbers)
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}
