/// JibJab Language Configuration
/// Loads shared language definition from common/jj.json
/// Loads target configs from common/targets/*.json
import Foundation

// Core config from jj.json (no targets)
struct JJCoreConfig: Codable {
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
        let `enum`: String
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
        let lte: Operator
        let gt: Operator
        let gte: Operator
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
        let cases: String
    }

    struct Literals: Codable {
        let numberPrefix: String
        let stringDelim: String
        let comment: String
    }
}

// Generic target config loaded from targets/*.json
struct TargetConfig: Codable {
    let name: String
    let ext: String
    let header: String
    private let _print: String?
    private let _printInt: String?
    private let _printStr: String?
    private let _printFloat: String?
    private let _printDouble: String?
    let `var`: String
    let varInfer: String?
    let varAuto: String?
    let forRange: String
    private let _forIn: String?
    let `while`: String
    let `if`: String
    let `else`: String
    let `func`: String
    private let _funcDecl: String?
    let `return`: String
    let call: String
    private let _blockEnd: String?
    let blockEndRepeat: String?
    let blockEndIf: String?
    let blockEndFunc: String?
    let indent: String
    let `true`: String
    let `false`: String
    let `nil`: String
    private let _and: String?
    private let _or: String?
    private let _not: String?
    private let _eq: String?
    private let _neq: String?
    private let _lte: String?
    private let _gte: String?
    private let _mod: String?
    let main: String?
    let types: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name, ext, header, `var`, varInfer, varAuto, forRange, `while`, `if`, `else`, `func`, `return`, call, indent, main, types
        case _print = "print"
        case _printInt = "printInt"
        case _printStr = "printStr"
        case _printFloat = "printFloat"
        case _printDouble = "printDouble"
        case _forIn = "forIn"
        case _funcDecl = "funcDecl"
        case _blockEnd = "blockEnd"
        case blockEndRepeat, blockEndIf, blockEndFunc
        case _and = "and"
        case _or = "or"
        case _not = "not"
        case _eq = "eq"
        case _neq = "neq"
        case _lte = "lte"
        case _gte = "gte"
        case _mod = "mod"
        // true/false/nil handled specially
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        ext = try container.decode(String.self, forKey: .ext)
        header = try container.decode(String.self, forKey: .header)
        _print = try container.decodeIfPresent(String.self, forKey: ._print)
        _printInt = try container.decodeIfPresent(String.self, forKey: ._printInt)
        _printStr = try container.decodeIfPresent(String.self, forKey: ._printStr)
        _printFloat = try container.decodeIfPresent(String.self, forKey: ._printFloat)
        _printDouble = try container.decodeIfPresent(String.self, forKey: ._printDouble)
        `var` = try container.decode(String.self, forKey: .var)
        varInfer = try container.decodeIfPresent(String.self, forKey: .varInfer)
        varAuto = try container.decodeIfPresent(String.self, forKey: .varAuto)
        forRange = try container.decode(String.self, forKey: .forRange)
        _forIn = try container.decodeIfPresent(String.self, forKey: ._forIn)
        `while` = try container.decode(String.self, forKey: .while)
        `if` = try container.decode(String.self, forKey: .if)
        `else` = try container.decode(String.self, forKey: .else)
        `func` = try container.decode(String.self, forKey: .func)
        _funcDecl = try container.decodeIfPresent(String.self, forKey: ._funcDecl)
        `return` = try container.decode(String.self, forKey: .return)
        call = try container.decode(String.self, forKey: .call)
        _blockEnd = try container.decodeIfPresent(String.self, forKey: ._blockEnd)
        blockEndRepeat = try container.decodeIfPresent(String.self, forKey: .blockEndRepeat)
        blockEndIf = try container.decodeIfPresent(String.self, forKey: .blockEndIf)
        blockEndFunc = try container.decodeIfPresent(String.self, forKey: .blockEndFunc)
        indent = try container.decode(String.self, forKey: .indent)
        main = try container.decodeIfPresent(String.self, forKey: .main)
        types = try container.decodeIfPresent([String: String].self, forKey: .types)
        _and = try container.decodeIfPresent(String.self, forKey: ._and)
        _or = try container.decodeIfPresent(String.self, forKey: ._or)
        _not = try container.decodeIfPresent(String.self, forKey: ._not)
        _eq = try container.decodeIfPresent(String.self, forKey: ._eq)
        _neq = try container.decodeIfPresent(String.self, forKey: ._neq)
        _lte = try container.decodeIfPresent(String.self, forKey: ._lte)
        _gte = try container.decodeIfPresent(String.self, forKey: ._gte)
        _mod = try container.decodeIfPresent(String.self, forKey: ._mod)

        // Handle true/false/nil with special decoder keys
        let additionalContainer = try decoder.container(keyedBy: AdditionalCodingKeys.self)
        `true` = try additionalContainer.decode(String.self, forKey: .trueKey)
        `false` = try additionalContainer.decode(String.self, forKey: .falseKey)
        `nil` = try additionalContainer.decode(String.self, forKey: .nilKey)
    }

    private enum AdditionalCodingKeys: String, CodingKey {
        case trueKey = "true"
        case falseKey = "false"
        case nilKey = "nil"
    }

    // Safe accessors with defaults
    var print: String { _print ?? _printInt ?? "" }
    var printInt: String { _printInt ?? _print ?? "" }
    var printStr: String { _printStr ?? _print ?? "" }
    var printFloat: String { _printFloat ?? _printInt ?? "" }
    var printDouble: String { _printDouble ?? _printInt ?? "" }
    var forIn: String { _forIn ?? forRange }
    var funcDecl: String { _funcDecl ?? `func` }
    var blockEnd: String { _blockEnd ?? "" }
    var and: String { _and ?? "&&" }
    var or: String { _or ?? "||" }
    var not: String { _not ?? "!" }
    var eq: String { _eq ?? "==" }
    var neq: String { _neq ?? "!=" }
    var lte: String { _lte ?? "<=" }
    var gte: String { _gte ?? ">=" }
    var mod: String { _mod ?? "%" }
}

/// Global JJ core configuration
let JJ: JJCoreConfig = {
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
                return try JSONDecoder().decode(JJCoreConfig.self, from: data)
            } catch {
                fatalError("Error parsing common/jj.json: \(error)")
            }
        }
    }
    fatalError("Could not find common/jj.json - run from jibjab directory")
}()

/// Load target config from common/targets/{name}.json
func loadTarget(_ name: String) -> TargetConfig {
    let cwd = FileManager.default.currentDirectoryPath
    let possiblePaths = [
        cwd + "/common/targets/\(name).json",
        cwd + "/../common/targets/\(name).json",
        cwd + "/../../common/targets/\(name).json",
    ]
    for path in possiblePaths {
        if FileManager.default.fileExists(atPath: path) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                return try JSONDecoder().decode(TargetConfig.self, from: data)
            } catch {
                fatalError("Error parsing common/targets/\(name).json: \(error)")
            }
        }
    }
    fatalError("Could not find common/targets/\(name).json")
}
