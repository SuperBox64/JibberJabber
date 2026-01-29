import SwiftUI
import JJLib

@main
struct BattleScriptApp: App {
    @AppStorage("showLineNumbers") private var showLineNumbers = true

    init() {
        JJEnv.basePath = Bundle.main.resourcePath! + "/common"
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                Toggle("Show Line Numbers", isOn: $showLineNumbers)
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}
