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
    private let _printBool: String?
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
    private let _try: String?
    private let _catch: String?
    private let _blockEndTry: String?
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
    private let _comment: String?
    private let _emptyBody: String?
    private let _interpOpen: String?
    private let _interpClose: String?
    private let _interpVarOpen: String?
    private let _interpVarClose: String?
    private let _interpConcat: String?
    private let _interpCast: String?
    private let _indexAccess: String?
    private let _propertyAccess: String?
    private let _enumAccess: String?
    private let _enumConst: String?
    private let _enumSelf: String?
    private let _reservedWords: [String]?
    private let _reservedPrefix: String?
    private let _stringInclude: String?
    private let _varDict: String?
    private let _dictEmpty: String?
    private let _paramFormat: String?
    private let _intFmt: String?
    private let _strFmt: String?
    private let _doubleFmt: String?
    private let _boolFmt: String?
    private let _printfInterp: String?
    private let _printfInline: String?
    private let _coutExpr: String?
    private let _coutEndl: String?
    private let _coutSep: String?
    private let _coutNewline: String?
    private let _coutInline: String?
    private let _importSingle: String?
    private let _importMulti: String?
    private let _importItem: String?
    private let _arrayLitOpen: String?
    private let _arrayLitClose: String?
    private let _dictLitOpen: String?
    private let _dictLitClose: String?
    private let _boxString: String?
    private let _boxValue: String?
    private let _arrayType: String?
    private let _loopIndexType: String?
    private let _strSelector: String?
    private let _doubleSelector: String?
    private let _intSelector: String?
    private let _selectorAccess: String?
    private let _fmtIntLabel: String?
    private let _fmtStrLabel: String?
    private let _fmtFloatLabel: String?
    private let _boolTrueLabel: String?
    private let _boolFalseLabel: String?
    private let _mainLabel: String?
    private let _printfSymbol: String?
    private let _pageDirective: String?
    private let _pageOffDirective: String?
    private let _fmtIntStr: String?
    private let _fmtStrStr: String?
    private let _fmtFloatStr: String?
    private let _varArray: String?
    private let _varArrayNested: String?
    private let _enumNames: String?
    private let _highlightKeywords: [String]?
    private let _highlightDeclKeywords: [String]?
    private let _highlightTypeKeywords: [String]?
    private let _highlightSelfKeywords: [String]?
    private let _highlightSystemFunctions: [String]?
    private let _highlightCommentPrefix: String?
    private let _highlightBlockCommentStart: String?
    private let _highlightBlockCommentEnd: String?
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
        case _printBool = "printBool"
        case _forIn = "forIn"
        case _funcDecl = "funcDecl"
        case _blockEnd = "blockEnd"
        case blockEndRepeat, blockEndIf, blockEndFunc
        case _try = "try"
        case _catch = "catch"
        case _blockEndTry = "blockEndTry"
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
        case _comment = "comment"
        case _emptyBody = "emptyBody"
        case _interpOpen = "interpOpen"
        case _interpClose = "interpClose"
        case _interpVarOpen = "interpVarOpen"
        case _interpVarClose = "interpVarClose"
        case _interpConcat = "interpConcat"
        case _interpCast = "interpCast"
        case _indexAccess = "indexAccess"
        case _propertyAccess = "propertyAccess"
        case _enumAccess = "enumAccess"
        case _enumConst = "enumConst"
        case _enumSelf = "enumSelf"
        case _reservedWords = "reservedWords"
        case _reservedPrefix = "reservedPrefix"
        case _stringInclude = "stringInclude"
        case _varDict = "varDict"
        case _dictEmpty = "dictEmpty"
        case _paramFormat = "paramFormat"
        case _intFmt = "intFmt"
        case _strFmt = "strFmt"
        case _doubleFmt = "doubleFmt"
        case _boolFmt = "boolFmt"
        case _printfInterp = "printfInterp"
        case _printfInline = "printfInline"
        case _coutExpr = "coutExpr"
        case _coutEndl = "coutEndl"
        case _coutSep = "coutSep"
        case _coutNewline = "coutNewline"
        case _coutInline = "coutInline"
        case _importSingle = "importSingle"
        case _importMulti = "importMulti"
        case _importItem = "importItem"
        case _arrayLitOpen = "arrayLitOpen"
        case _arrayLitClose = "arrayLitClose"
        case _dictLitOpen = "dictLitOpen"
        case _dictLitClose = "dictLitClose"
        case _boxString = "boxString"
        case _boxValue = "boxValue"
        case _arrayType = "arrayType"
        case _loopIndexType = "loopIndexType"
        case _strSelector = "strSelector"
        case _doubleSelector = "doubleSelector"
        case _intSelector = "intSelector"
        case _selectorAccess = "selectorAccess"
        case _fmtIntLabel = "fmtIntLabel"
        case _fmtStrLabel = "fmtStrLabel"
        case _fmtFloatLabel = "fmtFloatLabel"
        case _boolTrueLabel = "boolTrueLabel"
        case _boolFalseLabel = "boolFalseLabel"
        case _mainLabel = "mainLabel"
        case _printfSymbol = "printfSymbol"
        case _pageDirective = "pageDirective"
        case _pageOffDirective = "pageOffDirective"
        case _fmtIntStr = "fmtIntStr"
        case _fmtStrStr = "fmtStrStr"
        case _fmtFloatStr = "fmtFloatStr"
        case _varArray = "varArray"
        case _varArrayNested = "varArrayNested"
        case _enumNames = "enumNames"
        case _highlightKeywords = "highlightKeywords"
        case _highlightDeclKeywords = "highlightDeclKeywords"
        case _highlightTypeKeywords = "highlightTypeKeywords"
        case _highlightSelfKeywords = "highlightSelfKeywords"
        case _highlightSystemFunctions = "highlightSystemFunctions"
        case _highlightCommentPrefix = "highlightCommentPrefix"
        case _highlightBlockCommentStart = "highlightBlockCommentStart"
        case _highlightBlockCommentEnd = "highlightBlockCommentEnd"
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
        _printBool = try container.decodeIfPresent(String.self, forKey: ._printBool)
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
        _try = try container.decodeIfPresent(String.self, forKey: ._try)
        _catch = try container.decodeIfPresent(String.self, forKey: ._catch)
        _blockEndTry = try container.decodeIfPresent(String.self, forKey: ._blockEndTry)
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
        _comment = try container.decodeIfPresent(String.self, forKey: ._comment)
        _emptyBody = try container.decodeIfPresent(String.self, forKey: ._emptyBody)
        _interpOpen = try container.decodeIfPresent(String.self, forKey: ._interpOpen)
        _interpClose = try container.decodeIfPresent(String.self, forKey: ._interpClose)
        _interpVarOpen = try container.decodeIfPresent(String.self, forKey: ._interpVarOpen)
        _interpVarClose = try container.decodeIfPresent(String.self, forKey: ._interpVarClose)
        _interpConcat = try container.decodeIfPresent(String.self, forKey: ._interpConcat)
        _interpCast = try container.decodeIfPresent(String.self, forKey: ._interpCast)
        _indexAccess = try container.decodeIfPresent(String.self, forKey: ._indexAccess)
        _propertyAccess = try container.decodeIfPresent(String.self, forKey: ._propertyAccess)
        _enumAccess = try container.decodeIfPresent(String.self, forKey: ._enumAccess)
        _enumConst = try container.decodeIfPresent(String.self, forKey: ._enumConst)
        _enumSelf = try container.decodeIfPresent(String.self, forKey: ._enumSelf)
        _reservedWords = try container.decodeIfPresent([String].self, forKey: ._reservedWords)
        _reservedPrefix = try container.decodeIfPresent(String.self, forKey: ._reservedPrefix)
        _stringInclude = try container.decodeIfPresent(String.self, forKey: ._stringInclude)
        _varDict = try container.decodeIfPresent(String.self, forKey: ._varDict)
        _dictEmpty = try container.decodeIfPresent(String.self, forKey: ._dictEmpty)
        _paramFormat = try container.decodeIfPresent(String.self, forKey: ._paramFormat)
        _intFmt = try container.decodeIfPresent(String.self, forKey: ._intFmt)
        _strFmt = try container.decodeIfPresent(String.self, forKey: ._strFmt)
        _doubleFmt = try container.decodeIfPresent(String.self, forKey: ._doubleFmt)
        _boolFmt = try container.decodeIfPresent(String.self, forKey: ._boolFmt)
        _printfInterp = try container.decodeIfPresent(String.self, forKey: ._printfInterp)
        _printfInline = try container.decodeIfPresent(String.self, forKey: ._printfInline)
        _coutExpr = try container.decodeIfPresent(String.self, forKey: ._coutExpr)
        _coutEndl = try container.decodeIfPresent(String.self, forKey: ._coutEndl)
        _coutSep = try container.decodeIfPresent(String.self, forKey: ._coutSep)
        _coutNewline = try container.decodeIfPresent(String.self, forKey: ._coutNewline)
        _coutInline = try container.decodeIfPresent(String.self, forKey: ._coutInline)
        _importSingle = try container.decodeIfPresent(String.self, forKey: ._importSingle)
        _importMulti = try container.decodeIfPresent(String.self, forKey: ._importMulti)
        _importItem = try container.decodeIfPresent(String.self, forKey: ._importItem)
        _arrayLitOpen = try container.decodeIfPresent(String.self, forKey: ._arrayLitOpen)
        _arrayLitClose = try container.decodeIfPresent(String.self, forKey: ._arrayLitClose)
        _dictLitOpen = try container.decodeIfPresent(String.self, forKey: ._dictLitOpen)
        _dictLitClose = try container.decodeIfPresent(String.self, forKey: ._dictLitClose)
        _boxString = try container.decodeIfPresent(String.self, forKey: ._boxString)
        _boxValue = try container.decodeIfPresent(String.self, forKey: ._boxValue)
        _arrayType = try container.decodeIfPresent(String.self, forKey: ._arrayType)
        _loopIndexType = try container.decodeIfPresent(String.self, forKey: ._loopIndexType)
        _strSelector = try container.decodeIfPresent(String.self, forKey: ._strSelector)
        _doubleSelector = try container.decodeIfPresent(String.self, forKey: ._doubleSelector)
        _intSelector = try container.decodeIfPresent(String.self, forKey: ._intSelector)
        _selectorAccess = try container.decodeIfPresent(String.self, forKey: ._selectorAccess)
        _fmtIntLabel = try container.decodeIfPresent(String.self, forKey: ._fmtIntLabel)
        _fmtStrLabel = try container.decodeIfPresent(String.self, forKey: ._fmtStrLabel)
        _fmtFloatLabel = try container.decodeIfPresent(String.self, forKey: ._fmtFloatLabel)
        _boolTrueLabel = try container.decodeIfPresent(String.self, forKey: ._boolTrueLabel)
        _boolFalseLabel = try container.decodeIfPresent(String.self, forKey: ._boolFalseLabel)
        _mainLabel = try container.decodeIfPresent(String.self, forKey: ._mainLabel)
        _printfSymbol = try container.decodeIfPresent(String.self, forKey: ._printfSymbol)
        _pageDirective = try container.decodeIfPresent(String.self, forKey: ._pageDirective)
        _pageOffDirective = try container.decodeIfPresent(String.self, forKey: ._pageOffDirective)
        _fmtIntStr = try container.decodeIfPresent(String.self, forKey: ._fmtIntStr)
        _fmtStrStr = try container.decodeIfPresent(String.self, forKey: ._fmtStrStr)
        _fmtFloatStr = try container.decodeIfPresent(String.self, forKey: ._fmtFloatStr)
        _varArray = try container.decodeIfPresent(String.self, forKey: ._varArray)
        _varArrayNested = try container.decodeIfPresent(String.self, forKey: ._varArrayNested)
        _enumNames = try container.decodeIfPresent(String.self, forKey: ._enumNames)
        _highlightKeywords = try container.decodeIfPresent([String].self, forKey: ._highlightKeywords)
        _highlightDeclKeywords = try container.decodeIfPresent([String].self, forKey: ._highlightDeclKeywords)
        _highlightTypeKeywords = try container.decodeIfPresent([String].self, forKey: ._highlightTypeKeywords)
        _highlightSelfKeywords = try container.decodeIfPresent([String].self, forKey: ._highlightSelfKeywords)
        _highlightSystemFunctions = try container.decodeIfPresent([String].self, forKey: ._highlightSystemFunctions)
        _highlightCommentPrefix = try container.decodeIfPresent(String.self, forKey: ._highlightCommentPrefix)
        _highlightBlockCommentStart = try container.decodeIfPresent(String.self, forKey: ._highlightBlockCommentStart)
        _highlightBlockCommentEnd = try container.decodeIfPresent(String.self, forKey: ._highlightBlockCommentEnd)

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
    public var printBool: String { _printBool ?? _print ?? printInt }
    public var forIn: String { _forIn ?? forRange }
    public var funcDecl: String { _funcDecl ?? `func` }
    public var blockEnd: String { _blockEnd ?? "" }
    public var tryBlock: String { _try ?? "try {" }
    public var catchBlock: String { _catch ?? "} catch {" }
    public var blockEndTry: String? { _blockEndTry }
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
    public var comment: String { _comment ?? "//" }
    public var emptyBody: String? { _emptyBody }
    public var interpOpen: String? { _interpOpen }
    public var interpClose: String? { _interpClose }
    public var interpVarOpen: String? { _interpVarOpen }
    public var interpVarClose: String? { _interpVarClose }
    public var interpConcat: String? { _interpConcat }
    public var interpCast: String? { _interpCast }
    public var indexAccess: String { _indexAccess ?? "{array}[{index}]" }
    public var propertyAccess: String { _propertyAccess ?? "{object}[{key}]" }
    public var enumAccess: String { _enumAccess ?? "{key}" }
    public var enumConst: String? { _enumConst }
    public var enumSelf: String { _enumSelf ?? "{name}.self" }
    public var reservedWords: [String] { _reservedWords ?? [] }
    public var reservedPrefix: String { _reservedPrefix ?? "_" }
    public var stringInclude: String? { _stringInclude }
    public var varDict: String? { _varDict }
    public var dictEmpty: String { _dictEmpty ?? "{}" }
    public var paramFormat: String? { _paramFormat }
    public var intFmt: String { _intFmt ?? "%d" }
    public var strFmt: String { _strFmt ?? "%s" }
    public var doubleFmt: String { _doubleFmt ?? "%g" }
    public var boolFmt: String { _boolFmt ?? "%s" }
    public var printfInterp: String { _printfInterp ?? "printf(\"{fmt}\\n\"{args});" }
    public var printfInline: String { _printfInline ?? "printf(\"{fmt}\"{args});" }
    public var coutExpr: String { _coutExpr ?? "std::cout << {expr}" }
    public var coutEndl: String { _coutEndl ?? " << std::endl;" }
    public var coutSep: String { _coutSep ?? " << " }
    public var coutNewline: String { _coutNewline ?? "std::cout << {expr} << std::endl;" }
    public var coutInline: String { _coutInline ?? "std::cout << {expr};" }
    public var importSingle: String { _importSingle ?? "import \"{name}\"" }
    public var importMulti: String { _importMulti ?? "import (\n{imports}\n)" }
    public var importItem: String { _importItem ?? "\"{name}\"" }
    public var arrayLitOpen: String { _arrayLitOpen ?? "{" }
    public var arrayLitClose: String { _arrayLitClose ?? "}" }
    public var dictLitOpen: String { _dictLitOpen ?? "{" }
    public var dictLitClose: String { _dictLitClose ?? "}" }
    public var boxString: String? { _boxString }
    public var boxValue: String? { _boxValue }
    public var arrayType: String? { _arrayType }
    public var loopIndexType: String { _loopIndexType ?? "int" }
    public var strSelector: String? { _strSelector }
    public var doubleSelector: String? { _doubleSelector }
    public var intSelector: String? { _intSelector }
    public var selectorAccess: String? { _selectorAccess }
    public var fmtIntLabel: String { _fmtIntLabel ?? "_fmt_int" }
    public var fmtStrLabel: String { _fmtStrLabel ?? "_fmt_str" }
    public var fmtFloatLabel: String { _fmtFloatLabel ?? "_fmt_float" }
    public var boolTrueLabel: String { _boolTrueLabel ?? "_bool_true" }
    public var boolFalseLabel: String { _boolFalseLabel ?? "_bool_false" }
    public var mainLabel: String { _mainLabel ?? "_main" }
    public var printfSymbol: String { _printfSymbol ?? "_printf" }
    public var pageDirective: String { _pageDirective ?? "@PAGE" }
    public var pageOffDirective: String { _pageOffDirective ?? "@PAGEOFF" }
    public var fmtIntStr: String { _fmtIntStr ?? "%d\\n" }
    public var fmtStrStr: String { _fmtStrStr ?? "%s\\n" }
    public var fmtFloatStr: String { _fmtFloatStr ?? "%g\\n" }
    public var varArray: String? { _varArray }
    public var varArrayNested: String? { _varArrayNested }
    public var enumNames: String? { _enumNames }
    public var highlightKeywords: [String] { _highlightKeywords ?? [] }
    public var highlightDeclKeywords: [String] { _highlightDeclKeywords ?? [] }
    public var highlightTypeKeywords: [String] { _highlightTypeKeywords ?? [] }
    public var highlightSelfKeywords: [String] { _highlightSelfKeywords ?? [] }
    public var highlightSystemFunctions: [String] { _highlightSystemFunctions ?? [] }
    public var highlightCommentPrefix: String { _highlightCommentPrefix ?? "//" }
    public var highlightBlockCommentStart: String { _highlightBlockCommentStart ?? "/*" }
    public var highlightBlockCommentEnd: String { _highlightBlockCommentEnd ?? "*/" }
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

// MARK: - JJ Emit Helpers

/// Builds JJ output strings from config values
public struct JJEmit {
    public static func print(_ expr: String) -> String {
        "\(JJ.keywords.print)\(JJ.structure.action)\(JJ.syntax.emit)(\(expr))"
    }
    public static func snag(_ name: String, _ val: String) -> String {
        "\(JJ.keywords.snag){\(name)}\(JJ.structure.action)\(JJ.syntax.val)(\(val))"
    }
    public static func yeet(_ val: String) -> String {
        "\(JJ.keywords.yeet){\(val)}"
    }
    public static func invoke(_ name: String, _ args: String) -> String {
        "\(JJ.keywords.invoke){\(name)}\(JJ.structure.action)\(JJ.syntax.with)(\(args))"
    }
    public static func morph(_ name: String, _ params: String) -> String {
        "\(JJ.blocks.morph)\(name)(\(params))\(JJ.blockSuffix)"
    }
    public static func loop(_ v: String, _ start: String, _ end: String) -> String {
        "\(JJ.blocks.loop)\(v)\(JJ.structure.colon)\(start)\(JJ.structure.range)\(end)\(JJ.blockSuffix)"
    }
    public static func when(_ cond: String) -> String {
        "\(JJ.blocks.when)\(cond)\(JJ.blockSuffix)"
    }
    public static var `try`: String { JJ.blocks.try }
    public static var oops: String { JJ.blocks.oops }
    public static var `else`: String { JJ.blocks.else }
    public static var end: String { JJ.blocks.end }
    public static var comment: String { JJ.literals.comment }
}

// MARK: - JJ Regex Pattern Builders

/// Builds regex patterns from jj.json for syntax highlighting
public struct JJPatterns {
    private static func esc(_ s: String) -> String {
        NSRegularExpression.escapedPattern(for: s)
    }

    public static var keyword: String {
        let kw = JJ.keywords
        return [kw.print, kw.input, kw.snag, kw.invoke, kw.yeet, kw.enum].map { keyword in
            if let braceIdx = keyword.firstIndex(of: "{") {
                return esc(String(keyword[..<braceIdx])) + "\\{[a-zA-Z0-9]*\\}"
            }
            return esc(keyword)
        }.joined(separator: "|")
    }

    public static var block: String {
        let blk = JJ.blocks
        let open = [blk.loop, blk.when, blk.morph].map { esc($0) }
        let closed = [blk.else, blk.try, blk.oops, blk.end].map { esc($0) }
        return (open + closed + [esc(JJ.blockSuffix)]).joined(separator: "|")
    }

    public static var `operator`: String {
        let ops = JJ.operators
        return [ops.lte, ops.gte, ops.neq, ops.and, ops.or,
                ops.eq, ops.lt, ops.gt, ops.add, ops.sub,
                ops.mul, ops.div, ops.mod, ops.not]
            .map { esc($0.symbol) }
            .joined(separator: "|")
    }

    public static var special: String {
        [JJ.keywords.true, JJ.keywords.false, JJ.keywords.nil]
            .map { esc($0) }
            .joined(separator: "|")
    }

    public static var action: String {
        let syn = JJ.syntax
        let actions = [syn.emit, syn.grab, syn.val, syn.with, syn.cases]
        return "\(esc(JJ.structure.action))(\(actions.map { esc($0) }.joined(separator: "|")))"
    }

    public static var separator: String {
        esc(JJ.structure.action)
    }

    public static var number: String {
        "\(esc(JJ.literals.numberPrefix))-?\\d+\\.?\\d*"
    }

    public static var comment: String {
        "\(esc(JJ.literals.comment)).*$"
    }
}
