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
    let targets: Targets

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

    struct Targets: Codable {
        let py: TargetPy
        let js: TargetJS
        let c: TargetC
    }

    struct TargetPy: Codable {
        let name: String
        let ext: String
        let header: String
        let print: String
        let `var`: String
        let forRange: String
        let forIn: String
        let `while`: String
        let `if`: String
        let `else`: String
        let `func`: String
        let `return`: String
        let call: String
        let indent: String
        let `true`: String
        let `false`: String
        let `nil`: String
        let and: String
        let or: String
        let not: String
    }

    struct TargetJS: Codable {
        let name: String
        let ext: String
        let header: String
        let print: String
        let `var`: String
        let forRange: String
        let forIn: String
        let `while`: String
        let `if`: String
        let `else`: String
        let `func`: String
        let `return`: String
        let call: String
        let blockEnd: String
        let indent: String
        let `true`: String
        let `false`: String
        let `nil`: String
        let eq: String
        let neq: String
    }

    struct TargetC: Codable {
        let name: String
        let ext: String
        let header: String
        let printInt: String
        let printStr: String
        let `var`: String
        let forRange: String
        let `while`: String
        let `if`: String
        let `else`: String
        let `func`: String
        let funcDecl: String
        let `return`: String
        let call: String
        let blockEnd: String
        let indent: String
        let `true`: String
        let `false`: String
        let `nil`: String
        let main: String
    }
}

/// Global JJ configuration - MUST load from common/jj.json
let JJ: JJConfig = {
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
