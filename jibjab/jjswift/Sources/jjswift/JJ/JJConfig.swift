/// JibJab Language Configuration
/// Loads shared language definition from common/jj.json
import Foundation

struct JJConfig: Codable {
    let version: String
    let keywords: Keywords
    let blocks: Blocks
    let blockSuffix: String
    let operators: Operators
    let structure: Structure
    let syntax: Syntax
    let literals: Literals

    struct Keywords: Codable {
        let print: String
        let input: String
        let yeet: String
        let snag: String
        let invoke: String
        let `nil`: String
        let `true`: String
        let `false`: String
    }

    struct Blocks: Codable {
        let loop: String
        let when: String
        let `else`: String
        let morph: String
        let `try`: String
        let oops: String
        let end: String
    }

    struct Operator: Codable {
        let symbol: String
        let emit: String
    }

    struct Operators: Codable {
        let add: Operator
        let sub: Operator
        let mul: Operator
        let div: Operator
        let mod: Operator
        let eq: Operator
        let neq: Operator
        let lt: Operator
        let gt: Operator
        let and: Operator
        let or: Operator
        let not: Operator
    }

    struct Structure: Codable {
        let action: String
        let range: String
        let colon: String
    }

    struct Syntax: Codable {
        let emit: String
        let grab: String
        let val: String
        let with: String
    }

    struct Literals: Codable {
        let numberPrefix: String
        let stringDelim: String
        let comment: String
    }
}

/// Global JJ configuration loaded from common/jj.json
let JJ: JJConfig = {
    let possiblePaths = [
        // When running from jjswift directory
        "../../common/jj.json",
        "../common/jj.json",
        "common/jj.json",
        // Absolute fallback paths
        FileManager.default.currentDirectoryPath + "/../common/jj.json",
        FileManager.default.currentDirectoryPath + "/../../common/jj.json",
    ]

    // Also try relative to executable
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let execDir = executableURL.deletingLastPathComponent()
    let additionalPaths = [
        execDir.appendingPathComponent("../../../common/jj.json").path,
        execDir.appendingPathComponent("../../../../common/jj.json").path,
        execDir.appendingPathComponent("../../../../../common/jj.json").path,
    ]

    let allPaths = possiblePaths + additionalPaths

    for path in allPaths {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(JJConfig.self, from: data)
            } catch {
                continue
            }
        }
    }

    // Fallback: embedded defaults
    return JJConfig(
        version: "1.0.0",
        keywords: JJConfig.Keywords(
            print: "~>frob{7a3}",
            input: "~>slurp{9f2}",
            yeet: "~>yeet",
            snag: "~>snag",
            invoke: "~>invoke",
            nil: "~nil",
            true: "~yep",
            false: "~nope"
        ),
        blocks: JJConfig.Blocks(
            loop: "<~loop{",
            when: "<~when{",
            else: "<~else>>",
            morph: "<~morph{",
            try: "<~try>>",
            oops: "<~oops>>",
            end: "<~>>"
        ),
        blockSuffix: "}>>",
        operators: JJConfig.Operators(
            add: JJConfig.Operator(symbol: "<+>", emit: "+"),
            sub: JJConfig.Operator(symbol: "<->", emit: "-"),
            mul: JJConfig.Operator(symbol: "<*>", emit: "*"),
            div: JJConfig.Operator(symbol: "</>", emit: "/"),
            mod: JJConfig.Operator(symbol: "<%>", emit: "%"),
            eq: JJConfig.Operator(symbol: "<=>", emit: "=="),
            neq: JJConfig.Operator(symbol: "<!=>", emit: "!="),
            lt: JJConfig.Operator(symbol: "<lt>", emit: "<"),
            gt: JJConfig.Operator(symbol: "<gt>", emit: ">"),
            and: JJConfig.Operator(symbol: "<&&>", emit: "&&"),
            or: JJConfig.Operator(symbol: "<||>", emit: "||"),
            not: JJConfig.Operator(symbol: "<!>", emit: "!")
        ),
        structure: JJConfig.Structure(
            action: "::",
            range: "..",
            colon: ":"
        ),
        syntax: JJConfig.Syntax(
            emit: "emit",
            grab: "grab",
            val: "val",
            with: "with"
        ),
        literals: JJConfig.Literals(
            numberPrefix: "#",
            stringDelim: "\"",
            comment: "@@"
        )
    )
}()
