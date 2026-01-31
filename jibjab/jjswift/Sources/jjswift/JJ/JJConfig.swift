/// JibJab Language Configuration
/// Loads shared language definition from common/jj.json
/// Loads target configs from common/targets/*.json
import Foundation

// Core config from jj.json (no targets)
public struct JJCoreConfig: Codable {
    public let version: String
    public let keywords: Keywords
    public let blocks: Blocks
    public let blockSuffix: String
    public let operators: Operators
    public let structure: Structure
    public let syntax: Syntax
    public let literals: Literals

    public struct Keywords: Codable {
        public let print: String
        public let input: String
        public let yeet: String
        public let snag: String
        public let invoke: String
        public let `enum`: String
        public let `nil`: String
        public let `true`: String
        public let `false`: String
    }

    public struct Blocks: Codable {
        public let loop: String
        public let when: String
        public let `else`: String
        public let morph: String
        public let `try`: String
        public let oops: String
        public let end: String
    }

    public struct Operator: Codable {
        public let symbol: String
        public let emit: String
    }

    public struct Operators: Codable {
        public let add: Operator
        public let sub: Operator
        public let mul: Operator
        public let div: Operator
        public let mod: Operator
        public let eq: Operator
        public let neq: Operator
        public let lt: Operator
        public let lte: Operator
        public let gt: Operator
        public let gte: Operator
        public let and: Operator
        public let or: Operator
        public let not: Operator
    }

    public struct Structure: Codable {
        public let action: String
        public let range: String
        public let colon: String
    }

    public struct Syntax: Codable {
        public let emit: String
        public let grab: String
        public let val: String
        public let with: String
        public let cases: String
    }

    public struct Literals: Codable {
        public let numberPrefix: String
        public let stringDelim: String
        public let comment: String
    }

    public let validHashes: [String: String]?
    public let tokenSymbols: [String: String]?
}

// Generic target config loaded from targets/*.json
public struct TargetConfig: Codable {
    public let name: String
    public let ext: String
    public let header: String
    private let _print: String?
    private let _printInt: String?
    private let _printStr: String?
    private let _printFloat: String?
    private let _printDouble: String?
    public let `var`: String
    public let varInfer: String?
    public let varAuto: String?
    public let forRange: String
    private let _forIn: String?
    public let `while`: String
    public let `if`: String
    public let `else`: String
    public let `func`: String
    private let _funcDecl: String?
    public let `return`: String
    public let call: String
    private let _blockEnd: String?
    public let blockEndRepeat: String?
    public let blockEndIf: String?
    public let blockEndFunc: String?
    public let indent: String
    public let `true`: String
    public let `false`: String
    public let `nil`: String
    private let _and: String?
    private let _or: String?
    private let _not: String?
    private let _eq: String?
    private let _neq: String?
    private let _lte: String?
    private let _gte: String?
    private let _mod: String?
    private let _stringType: String?
    private let _floatMod: String?
    private let _enum: String?
    private let _enumStyle: String?
    private let _collectionStyle: String?
    private let _varShort: String?
    private let _expandBoolAsInt: Bool?
    private let _expandStringType: String?
    public let main: String?
    public let compile: [String]?
    public let run: [String]?
    public let types: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name, ext, header, `var`, varInfer, varAuto, forRange, `while`, `if`, `else`, `func`, `return`, call, indent, main, compile, run, types
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
        case _stringType = "stringType"
        case _floatMod = "floatMod"
        case _enum = "enum"
        case _enumStyle = "enumStyle"
        case _collectionStyle = "collectionStyle"
        case _varShort = "varShort"
        case _expandBoolAsInt = "expandBoolAsInt"
        case _expandStringType = "expandStringType"
        // true/false/nil handled specially
    }

    public init(from decoder: Decoder) throws {
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
        compile = try container.decodeIfPresent([String].self, forKey: .compile)
        run = try container.decodeIfPresent([String].self, forKey: .run)
        types = try container.decodeIfPresent([String: String].self, forKey: .types)
        _and = try container.decodeIfPresent(String.self, forKey: ._and)
        _or = try container.decodeIfPresent(String.self, forKey: ._or)
        _not = try container.decodeIfPresent(String.self, forKey: ._not)
        _eq = try container.decodeIfPresent(String.self, forKey: ._eq)
        _neq = try container.decodeIfPresent(String.self, forKey: ._neq)
        _lte = try container.decodeIfPresent(String.self, forKey: ._lte)
        _gte = try container.decodeIfPresent(String.self, forKey: ._gte)
        _mod = try container.decodeIfPresent(String.self, forKey: ._mod)
        _stringType = try container.decodeIfPresent(String.self, forKey: ._stringType)
        _floatMod = try container.decodeIfPresent(String.self, forKey: ._floatMod)
        _enum = try container.decodeIfPresent(String.self, forKey: ._enum)
        _enumStyle = try container.decodeIfPresent(String.self, forKey: ._enumStyle)
        _collectionStyle = try container.decodeIfPresent(String.self, forKey: ._collectionStyle)
        _varShort = try container.decodeIfPresent(String.self, forKey: ._varShort)
        _expandBoolAsInt = try container.decodeIfPresent(Bool.self, forKey: ._expandBoolAsInt)
        _expandStringType = try container.decodeIfPresent(String.self, forKey: ._expandStringType)

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
    public var print: String { _print ?? _printInt ?? "" }
    public var printInt: String { _printInt ?? _print ?? "" }
    public var printStr: String { _printStr ?? _print ?? "" }
    public var printFloat: String { _printFloat ?? _printInt ?? "" }
    public var printDouble: String { _printDouble ?? _printInt ?? "" }
    public var forIn: String { _forIn ?? forRange }
    public var funcDecl: String { _funcDecl ?? `func` }
    public var blockEnd: String { _blockEnd ?? "" }
    public var and: String { _and ?? "&&" }
    public var or: String { _or ?? "||" }
    public var not: String { _not ?? "!" }
    public var eq: String { _eq ?? "==" }
    public var neq: String { _neq ?? "!=" }
    public var lte: String { _lte ?? "<=" }
    public var gte: String { _gte ?? ">=" }
    public var mod: String { _mod ?? "%" }
    public var stringType: String { _stringType ?? "const char*" }
    public var floatMod: String? { _floatMod }
    public var enumTemplate: String? { _enum }
    public var enumStyle: String { _enumStyle ?? "template" }
    public var collectionStyle: String { _collectionStyle ?? "expand" }
    public var varShort: String? { _varShort }
    public var expandBoolAsInt: Bool { _expandBoolAsInt ?? false }
    public var expandStringType: String { _expandStringType ?? stringType }
}

/// Environment overrides for JJLib
public enum JJEnv {
    /// Override base path for config files. When set, JJLib loads from this path
    /// instead of searching relative to cwd. Set to the directory containing jj.json.
    public static var basePath: String?
}

/// Global JJ core configuration
public let JJ: JJCoreConfig = {
    var possiblePaths: [String]
    if let base = JJEnv.basePath {
        possiblePaths = [base + "/jj.json"]
    } else {
        let cwd = FileManager.default.currentDirectoryPath
        possiblePaths = [
            cwd + "/common/jj.json",
            cwd + "/../common/jj.json",
            cwd + "/../../common/jj.json",
        ]
    }
    for path in possiblePaths {
        if FileManager.default.fileExists(atPath: path) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                return try JSONDecoder().decode(JJCoreConfig.self, from: data)
            } catch {
                print("Error parsing common/jj.json: \(error)")
                exit(1)
            }
        }
    }
    print("Error: could not find common/jj.json - run from jibjab directory")
    exit(1)
}()

/// Load target config from common/targets/{name}.json
public func loadTarget(_ name: String) -> TargetConfig {
    var possiblePaths: [String]
    if let base = JJEnv.basePath {
        possiblePaths = [base + "/targets/\(name).json"]
    } else {
        let cwd = FileManager.default.currentDirectoryPath
        possiblePaths = [
            cwd + "/common/targets/\(name).json",
            cwd + "/../common/targets/\(name).json",
            cwd + "/../../common/targets/\(name).json",
        ]
    }
    for path in possiblePaths {
        if FileManager.default.fileExists(atPath: path) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let config = try? JSONDecoder().decode(TargetConfig.self, from: data) else {
                print("Error: failed to parse common/targets/\(name).json")
                exit(1)
            }
            return config
        }
    }
    print("Error: could not find common/targets/\(name).json")
    exit(1)
}

/// Re-escape a string value for code emission.
/// The lexer converts \n to actual newline, etc. — this converts back
/// so transpiled source contains the escape sequences.
public func escapeString(_ s: String) -> String {
    var result = ""
    for ch in s {
        switch ch {
        case "\\": result += "\\\\"
        case "\"": result += "\\\""
        case "\n": result += "\\n"
        case "\t": result += "\\t"
        case "\r": result += "\\r"
        default: result.append(ch)
        }
    }
    return result
}
