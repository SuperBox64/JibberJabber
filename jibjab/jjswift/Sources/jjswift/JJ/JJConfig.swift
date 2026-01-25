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

/// Global JJ configuration - MUST load from common/jj.json
let JJ: JJConfig = {
    // Find the common/jj.json file
    let cwd = FileManager.default.currentDirectoryPath

    let possiblePaths = [
        cwd + "/common/jj.json",
        cwd + "/../common/jj.json",
        cwd + "/../../common/jj.json",
    ]

    for path in possiblePaths {
        if FileManager.default.fileExists(atPath: path) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                return try JSONDecoder().decode(JJConfig.self, from: data)
            } catch {
                fatalError("Error parsing common/jj.json: \(error)")
            }
        }
    }

    fatalError("Could not find common/jj.json - run from jibjab directory")
}()
