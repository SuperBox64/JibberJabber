import Foundation

struct DependencyStatus {
    let xcodeTools: Bool
    let go: Bool
    let quickjs: Bool

    var allGood: Bool { xcodeTools && go && quickjs }
}

struct DependencyChecker {
    private static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/local/go/bin",
        "/opt/local/bin",
    ]

    private static func findTool(_ name: String) -> Bool {
        let fm = FileManager.default
        return searchPaths.contains { fm.fileExists(atPath: "\($0)/\(name)") }
    }

    static func check() -> DependencyStatus {
        let xcodeTools = FileManager.default.fileExists(atPath: "/usr/bin/clang")
        let go = findTool("go")
        let quickjs = findTool("qjs") && findTool("qjsc")
        return DependencyStatus(xcodeTools: xcodeTools, go: go, quickjs: quickjs)
    }
}
