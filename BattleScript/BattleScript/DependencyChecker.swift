import Foundation

struct DependencyStatus {
    let xcodeTools: Bool
    let go: Bool
    let quickjs: Bool

    var allGood: Bool { xcodeTools && go && quickjs }
}

struct DependencyChecker {
    static func check() -> DependencyStatus {
        let fm = FileManager.default
        let xcodeTools = fm.fileExists(atPath: "/usr/bin/clang")
        let go = fm.fileExists(atPath: "/opt/homebrew/bin/go") || fm.fileExists(atPath: "/usr/local/bin/go")
        let quickjs = fm.fileExists(atPath: "/opt/homebrew/bin/qjsc") || fm.fileExists(atPath: "/usr/local/bin/qjsc")
        return DependencyStatus(xcodeTools: xcodeTools, go: go, quickjs: quickjs)
    }
}
