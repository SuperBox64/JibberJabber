/// Generates reverse transpiler regex patterns from target JSON configs.
/// Instead of hard-coding target language keywords (type names, print functions,
/// loop syntax, etc.), each pattern is derived from the forward transpiler templates.
import Foundation

public struct ReversePatterns {

    private static func esc(_ s: String) -> String {
        NSRegularExpression.escapedPattern(for: s)
    }

    // MARK: - Type Alternation

    /// Builds a regex alternation of all type values from the target config.
    /// E.g. "(?:int|float|double|const char\\*|void)"
    public static func typeAlternation(_ target: TargetConfig) -> String {
        var types = Set<String>()
        if let dict = target.types {
            for v in dict.values { types.insert(v) }
        }
        types.insert(target.stringType)
        types.insert(target.expandStringType)
        types.insert("void")
        // Sort longest first so regex is greedy on longer matches
        let sorted = types.sorted { $0.count > $1.count }
        let escaped = sorted.map { esc($0) }
        return "(?:\(escaped.joined(separator: "|")))"
    }

    // MARK: - Header Patterns

    /// Extracts non-empty header line prefixes for stripping during reverse transpile.
    public static func headerPatterns(_ target: TargetConfig) -> [String] {
        target.header
            .components(separatedBy: "\\n")
            .flatMap { $0.components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Comment Prefix

    /// Derives the comment prefix from the target header (// or # or --).
    public static func commentPrefix(_ target: TargetConfig) -> String {
        let header = target.header
        if header.hasPrefix("//") { return "//" }
        if header.hasPrefix("#!") || header.hasPrefix("# ") || header.hasPrefix("#\n") { return "#" }
        if header.hasPrefix("--") { return "--" }
        return "//"
    }

    // MARK: - Main Pattern

    /// Extracts the main function signature for matching (e.g. "int main()" or "func main()").
    /// Returns nil if the target has no main wrapper.
    public static func mainSignature(_ target: TargetConfig) -> String? {
        guard let main = target.main else { return nil }
        // Take up to first \n or {
        let lines = main.components(separatedBy: "\\n").first
            ?? main.components(separatedBy: "\n").first
            ?? main
        var sig = lines
        if let braceIdx = sig.firstIndex(of: "{") {
            sig = String(sig[..<braceIdx]).trimmingCharacters(in: .whitespaces)
        }
        // Strip {body} and everything after
        if let bodyIdx = sig.range(of: "{body}") {
            sig = String(sig[..<bodyIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return sig.isEmpty ? nil : sig
    }

    // MARK: - Print Pattern

    /// Generates a regex to match print statements from the target's print template.
    /// Captures the expression being printed.
    public static func printPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let template = target.printInt
        if template.isEmpty { return nil }

        // printf-style: printf("%d\n", expr);
        if template.contains("printf") {
            // Match printf with any format specifier, optional cast like (long)
            return try? NSRegularExpression(
                pattern: "^printf\\(\"%[a-z]*\\\\n\",\\s*(?:\\(long\\))?(.+)\\);$"
            )
        }

        // cout-style: std::cout << expr << std::endl;
        if template.contains("std::cout") {
            return try? NSRegularExpression(
                pattern: "^std::cout\\s*<<\\s*(.+?)\\s*<<\\s*std::endl;$"
            )
        }

        // fmt.Println-style
        if template.contains("fmt.Println") {
            return try? NSRegularExpression(pattern: "^fmt\\.Println\\((.+)\\)$")
        }

        // console.log-style
        if template.contains("console.log") {
            return try? NSRegularExpression(pattern: "^console\\.log\\((.+)\\);$")
        }

        // log expr (AppleScript)
        if template.hasPrefix("log ") {
            return try? NSRegularExpression(pattern: "^log\\s+(.+)$")
        }

        // Generic function-style: funcName(expr) with optional semicolon
        // Extract the function name from template
        let funcTemplate = template.replacingOccurrences(of: "{expr}", with: "PLACEHOLDER")
        if let parenIdx = funcTemplate.firstIndex(of: "(") {
            let funcName = String(funcTemplate[..<parenIdx])
            let hasSemicolon = template.hasSuffix(";")
            let semi = hasSemicolon ? "?" : ""
            return try? NSRegularExpression(
                pattern: "^\(esc(funcName))\\((.+)\\);?\(semi)$"
            )
        }

        return nil
    }

    /// Generates a regex for printf + cout dual print (ObjC++).
    /// Returns a pattern that matches either printf or cout style.
    public static func dualPrintPattern(printf: TargetConfig, cout: TargetConfig) -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: "^(?:printf\\(\"%[a-z]*\\\\n\",\\s*(?:\\(long\\))?(.+)\\)|std::cout\\s*<<\\s*(.+?)\\s*<<\\s*std::endl);$"
        )
    }

    // MARK: - Variable Pattern

    /// Generates a regex to match variable declarations from the target's var template.
    /// Capture group 1 = name, capture group 2 = value.
    public static func varPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let template = target.var

        // Python-style: {name} = {value}
        if template == "{name} = {value}" {
            return try? NSRegularExpression(
                pattern: "^([a-zA-Z_][a-zA-Z0-9_]*)\\s*=\\s*(.+)$"
            )
        }

        // AppleScript: set {name} to {value}
        if template.hasPrefix("set ") {
            return try? NSRegularExpression(
                pattern: "^set\\s+(\\w+)\\s+to\\s+(.+)$"
            )
        }

        // Type-prefixed: {type} {name} = {value}; (C, C++, ObjC, ObjC++)
        if template.contains("{type}") {
            let types = typeAlternation(target)
            let hasSemicolon = template.hasSuffix(";")
            // Also handle varAuto/varInfer patterns
            var patterns = ["\(types)\\s+(\\w+)\\s*=\\s*(.+?)\(hasSemicolon ? ";" : "")$"]

            // Add auto/var keyword patterns if available
            if let varAuto = target.varAuto {
                if varAuto.hasPrefix("auto ") {
                    patterns.append("auto\\s+(\\w+)\\s*=\\s*(.+?);$")
                }
            }
            if let varInfer = target.varInfer {
                // Swift: var {name} = {value}
                if varInfer.hasPrefix("var ") {
                    patterns.append("var\\s+(\\w+)\\s*=\\s*(.+)$")
                }
            }

            let combined = patterns.joined(separator: "|")
            return try? NSRegularExpression(pattern: "^(?:\(combined))")
        }

        // Keyword-prefixed: let/var/const {name} = {value};
        let keywords = ["let", "const", "var"]
        for kw in keywords {
            if template.hasPrefix("\(kw) ") {
                let hasSemicolon = template.hasSuffix(";")
                // For Swift var with optional type: var {name}: {type} = {value}
                if template.contains(": {type}") {
                    let types = typeAlternation(target)
                    return try? NSRegularExpression(
                        pattern: "^var\\s+(\\w+)(?:\\s*:\\s*\(types))?\\s*=\\s*(.+)\(hasSemicolon ? ";" : "")$"
                    )
                }
                return try? NSRegularExpression(
                    pattern: "^(?:let|const|var)\\s+(\\w+)\\s*=\\s*(.+)\(hasSemicolon ? ";" : "")$"
                )
            }
        }

        // Go-style: var {name} {type} = {value} or {name} := {value}
        if template.hasPrefix("var ") && template.contains("{type}") {
            // Match both var x type = val and x := val
            return try? NSRegularExpression(
                pattern: "^(?:var\\s+)?(\\w+)\\s*:?=\\s*(.+)$"
            )
        }

        return nil
    }

    // MARK: - For Loop Pattern

    /// Generates a regex to match for-range loops. Captures: 1=var, 2=start, 3=end.
    public static func forPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let template = target.forRange

        // C-style: for (int {var} = {start}; {var} < {end}; {var}++) {
        if template.contains("for (") || template.contains("for(") {
            // Extract the iterator type keyword from template
            let afterParen = template.components(separatedBy: "(").dropFirst().joined(separator: "(")
            let iterType: String
            if afterParen.hasPrefix("int ") {
                iterType = "int"
            } else if afterParen.hasPrefix("let ") {
                iterType = "let"
            } else {
                iterType = "\\w+"
            }
            return try? NSRegularExpression(
                pattern: "^for\\s*\\(\(esc(iterType))\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"
            )
        }

        // Swift: for {var} in {start}..<{end} {
        if template.contains("..<") {
            return try? NSRegularExpression(
                pattern: "^for\\s+(\\w+)\\s+in\\s+(\\d+)\\.\\.<(\\d+)\\s*\\{$"
            )
        }

        // Go: for {var} := {start}; {var} < {end}; {var}++ {
        if template.contains(":=") {
            return try? NSRegularExpression(
                pattern: "^for\\s+(\\w+)\\s*:=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"
            )
        }

        // Python: for {var} in range({start}, {end}):
        if template.contains("range(") {
            return try? NSRegularExpression(
                pattern: "^for\\s+(\\w+)\\s+in\\s+range\\((\\d+),\\s*(\\d+)\\):$"
            )
        }

        // AppleScript: repeat with {var} from {start} to ({end} - 1)
        if template.contains("repeat with") {
            return try? NSRegularExpression(
                pattern: "^repeat\\s+with\\s+(\\w+)\\s+from\\s+(\\d+)\\s+to\\s+\\((\\d+)\\s*-\\s*1\\)$"
            )
        }

        return nil
    }

    // MARK: - If Pattern

    /// Generates a regex to match if statements. Captures: 1=condition.
    public static func ifPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let template = target.if

        // C-style: if ({condition}) {
        if template.contains("({condition})") {
            return try? NSRegularExpression(pattern: "^if\\s*\\((.+)\\)\\s*\\{$")
        }

        // Swift/Go: if {condition} {
        if template.hasSuffix("{condition} {") {
            return try? NSRegularExpression(pattern: "^if\\s+(.+?)\\s*\\{$")
        }

        // Python: if {condition}:
        if template.hasSuffix(":") {
            return try? NSRegularExpression(pattern: "^if\\s+(.+):$")
        }

        // AppleScript: if {condition} then
        if template.hasSuffix("then") {
            return try? NSRegularExpression(pattern: "^if\\s+(.+?)\\s+then$")
        }

        return nil
    }

    // MARK: - Else Pattern

    /// Generates a regex to match else statements.
    public static func elsePattern(_ target: TargetConfig) -> NSRegularExpression? {
        let template = target.else

        // } else {
        if template.contains("}") && template.contains("{") {
            return try? NSRegularExpression(pattern: "^\\}?\\s*else\\s*\\{?$")
        }

        // else:
        if template == "else:" {
            return try? NSRegularExpression(pattern: "^else:$")
        }

        // bare else (AppleScript)
        return try? NSRegularExpression(pattern: "^else$")
    }

    // MARK: - Function Pattern

    /// Generates a regex to match function definitions.
    /// Captures: 1=name, 2=params.
    public static func funcPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let template = target.func

        // Python: def {name}({params}):
        if template.hasPrefix("def ") {
            return try? NSRegularExpression(
                pattern: "^def\\s+(\\w+)\\(([^)]*)\\):$"
            )
        }

        // AppleScript: on {name}({params})
        if template.hasPrefix("on ") {
            return try? NSRegularExpression(
                pattern: "^on\\s+(\\w+)\\(([^)]*)\\)$"
            )
        }

        // JavaScript: function {name}({params}) {
        if template.hasPrefix("function ") {
            return try? NSRegularExpression(
                pattern: "^function\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"
            )
        }

        // Swift: func {name}({params}) -> Int {
        if template.hasPrefix("func ") {
            return try? NSRegularExpression(
                pattern: "^func\\s+(\\w+)\\(([^)]*)\\)(?:\\s*->\\s*\\w+)?\\s*\\{$"
            )
        }

        // C-family: {type} {name}({params}) {
        if template.contains("{type}") {
            let types = typeAlternation(target)
            return try? NSRegularExpression(
                pattern: "^\(types)\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"
            )
        }

        // Go: func {name}({params}) {type} {
        // Already handled by "func " prefix above, but Go has return type after params
        return nil
    }

    // MARK: - Forward Declaration Pattern

    /// Generates a regex to match forward declarations (C, C++, ObjC).
    /// Returns nil for languages without forward declarations.
    public static func funcDeclPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let decl = target.funcDecl
        if decl.isEmpty { return nil }
        // Same as func template but ending with ; instead of {
        if !decl.hasSuffix(";") { return nil }

        if decl.contains("{type}") {
            let types = typeAlternation(target)
            return try? NSRegularExpression(
                pattern: "^\(types)\\s+\\w+\\([^)]*\\);$"
            )
        }
        return nil
    }

    // MARK: - Return Pattern

    /// Generates a regex to match return statements. Captures: 1=value.
    public static func returnPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let hasSemicolon = target.return.hasSuffix(";")
        return try? NSRegularExpression(
            pattern: "^return\\s+(.+?)\\s*\(hasSemicolon ? ";?" : "")$"
        )
    }

    // MARK: - Throw Pattern

    /// Generates a regex to match throw/raise/panic statements. Captures: 1=value.
    public static func throwPattern(_ target: TargetConfig) -> NSRegularExpression? {
        guard let tmpl = target.throwStmt else { return nil }
        // Build pattern from template
        // "raise Exception({value})" -> ^raise Exception\((.+?)\)$
        // "throw {value};" -> ^throw (.+?);?$
        // "panic({value})" -> ^panic\((.+?)\)$
        // "@throw [NSException ...]" -> ^@throw .*$
        // "/* throw */ abort();" -> skip (no capture)
        // "error {value}" -> ^error (.+?)$
        let escaped = NSRegularExpression.escapedPattern(for: tmpl)
        let pattern = escaped
            .replacingOccurrences(of: "\\{value\\}", with: "(.+?)")
        let hasSemicolon = tmpl.hasSuffix(";")
        let finalPattern = hasSemicolon ? "^\(pattern.dropLast(1));?$" : "^\(pattern)$"
        return try? NSRegularExpression(pattern: finalPattern)
    }

    // MARK: - Bool Ternary Pattern

    /// Generates a regex for printf-style bool ternary:
    /// printf("%s\n", x ? "true" : "false");
    /// Returns nil for languages that don't use ternary in printBool.
    public static func printfBoolTernaryPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let template = target.printBool
        // Only applies to printf-style with ternary
        guard template.contains("printf") && template.contains("?") else { return nil }

        // Extract the true/false display strings from the template
        // Template looks like: printf("%s\n", {expr} ? "true" : "false");
        // The display strings are the quoted values after ? and :
        return try? NSRegularExpression(
            pattern: #"^(\s*)printf\("%s\\n",\s*(\w+)\s*\?\s*"[^"]*"\s*:\s*"[^"]*"\);$"#
        )
    }

    /// Generates a regex for cout-style bool ternary:
    /// std::cout << (x ? "true" : "false") << std::endl;
    /// Returns nil for languages that don't use ternary in printBool.
    public static func coutBoolTernaryPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let template = target.printBool
        guard template.contains("std::cout") && template.contains("?") else { return nil }

        return try? NSRegularExpression(
            pattern: #"^(\s*)std::cout\s*<<\s*\((\w+)\s*\?\s*"[^"]*"\s*:\s*"[^"]*"\)\s*<<\s*std::endl;$"#
        )
    }

    /// Generates a regex for inline bool ternary within multi-specifier printf:
    /// {x ? "true" : "false"} → {x}
    public static func inlineBoolTernaryPattern() -> NSRegularExpression? {
        try? NSRegularExpression(pattern: #"\{(\w+) \? "[^"]*" : "[^"]*"\}"#)
    }

    // MARK: - Python Bool Patterns

    /// Generates regex for Python's str(x).lower() bool print pattern.
    public static func pythonPrintBoolPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let template = target.printBool
        guard template.contains("str(") && template.contains(".lower()") else { return nil }
        return try? NSRegularExpression(pattern: #"^(\s*)print\(str\((\w+)\)\.lower\(\)\)$"#)
    }

    /// Generates regex for Python's f-string bool pattern: {str(x).lower()}.
    public static func pythonFStringBoolPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let template = target.printBool
        guard template.contains("str(") && template.contains(".lower()") else { return nil }
        return try? NSRegularExpression(pattern: #"\{str\((\w+)\)\.lower\(\)\}"#)
    }

    // MARK: - Known Functions

    /// Extracts known function names from the target's print templates
    /// plus standard library functions that shouldn't be reverse-transpiled as user calls.
    /// Also extracts keywords from the target's statement templates (for, if, def, etc.).
    public static func knownFunctions(_ target: TargetConfig) -> Set<String> {
        var funcs = Set<String>()

        // Extract function names from print templates
        for template in [target.print, target.printInt, target.printStr, target.printBool] {
            if let dotIdx = template.firstIndex(of: ".") {
                let prefix = String(template[..<dotIdx])
                if !prefix.contains("{") { funcs.insert(prefix) }
                let afterDot = template[template.index(after: dotIdx)...]
                if let parenIdx = afterDot.firstIndex(of: "(") {
                    let methodName = String(afterDot[..<parenIdx])
                    if !methodName.contains("{") { funcs.insert("\(prefix).\(methodName)") }
                }
            }
            if let parenIdx = template.firstIndex(of: "(") {
                let name = String(template[..<parenIdx])
                if !name.contains("{") && !name.isEmpty { funcs.insert(name) }
            }
        }

        // Extract statement keywords from templates
        // e.g. "def {name}({params}):" → "def", "for {var} in range..." → "for"
        let templates = [target.forRange, target.if, target.else, target.func,
                         target.return, target.while, target.var, target.call]
        for tmpl in templates {
            // First word before { or ( or space
            let firstWord = tmpl.prefix(while: { $0.isLetter || $0 == "_" })
            if !firstWord.isEmpty { funcs.insert(String(firstWord)) }
        }

        // If target has a main wrapper, "main" is a known function
        if target.main != nil { funcs.insert("main") }

        return funcs
    }

    // MARK: - Printf Multi-Specifier Pattern

    /// Generates regex for multi-specifier printf, derived from the target's print template.
    /// Returns nil for targets that don't use printf.
    public static func printfMultiPattern(_ target: TargetConfig) -> NSRegularExpression? {
        guard target.printInt.contains("printf") else { return nil }
        return try? NSRegularExpression(
            pattern: #"^(\s*)printf\("(.+)\\n"(?:,\s*(.+))?\);$"#
        )
    }

    // MARK: - Go Printf Pattern

    /// Generates regex for Go's fmt.Printf pattern, derived from the target's print template.
    /// Returns nil for non-Go targets.
    public static func fmtPrintfPattern(_ target: TargetConfig) -> NSRegularExpression? {
        guard target.printInt.contains("fmt.P") else { return nil }
        return try? NSRegularExpression(pattern: #"^(\s*)fmt\.Printf\("(.+)\\n"(?:,\s*(.+))?\)$"#)
    }

    // MARK: - Main Wrapper Helpers

    /// Whether the target's main template contains an @autoreleasepool wrapper.
    public static func hasAutoreleasepool(_ target: TargetConfig) -> Bool {
        target.main?.contains("@autoreleasepool") ?? false
    }

    /// Builds the "return 0;" string from the target's return template with value "0".
    /// Used to detect and skip the main wrapper's return statement.
    public static func mainReturnStatement(_ target: TargetConfig) -> String {
        target.return.replacingOccurrences(of: "{value}", with: "0")
    }

    /// The block-end string from the target (e.g. "}" for C-family).
    public static func blockEndString(_ target: TargetConfig) -> String {
        target.blockEnd
    }

    // MARK: - Cout Replacement

    /// Builds the cout print replacement string for a variable, derived from target's printInt template.
    /// E.g. for C++: "std::cout << varName << std::endl;"
    public static func coutReplacement(_ target: TargetConfig, varName: String) -> String? {
        guard target.printInt.contains("std::cout") else { return nil }
        return target.printInt.replacingOccurrences(of: "{expr}", with: varName)
    }

    /// Builds the printf print replacement string for a variable with %d format.
    /// E.g. for C: "printf("%d\n", varName);"
    public static func printfIntReplacement(_ target: TargetConfig, varName: String) -> String {
        target.printInt.replacingOccurrences(of: "{expr}", with: varName)
    }

    // MARK: - Comment Pattern

    /// Generates a regex to match comments for the given target.
    public static func commentPattern(_ target: TargetConfig) -> NSRegularExpression? {
        let prefix = commentPrefix(target)
        return try? NSRegularExpression(pattern: "^\(esc(prefix))\\s*(.*)$")
    }

    // MARK: - CatchVarBind Pattern

    /// Generates a regex from the target's catchVarBind template to extract the variable name.
    /// E.g. "let {var} = (error as? JJError)?.message ?? \"\\(error)\"" → captures the variable name.
    public static func catchVarBindPattern(_ target: TargetConfig) -> NSRegularExpression? {
        guard let tmpl = target.catchVarBind else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: tmpl)
        let pattern = escaped.replacingOccurrences(of: "\\{var\\}", with: "(\\w+)")
        let hasSemicolon = tmpl.hasSuffix(";")
        let finalPattern = hasSemicolon ? "^\(pattern.dropLast(1));?$" : "^\(pattern)$"
        return try? NSRegularExpression(pattern: finalPattern)
    }

    // MARK: - Operator Replacements

    /// Returns target-specific operator replacements for reverse transpiling.
    /// Maps target operator → JJ operator symbol.
    public static func operatorReplacements(_ target: TargetConfig) -> [(find: String, replace: String)] {
        var replacements: [(String, String)] = []
        let OP = JJ.operators

        // Custom operators from config (Python, AppleScript, JS, etc.)
        if target.and != "&&" {
            replacements.append((" \(target.and) ", " \(OP.and.symbol) "))
        }
        if target.or != "||" {
            replacements.append((" \(target.or) ", " \(OP.or.symbol) "))
        }
        if target.not != "!" {
            replacements.append((target.not, OP.not.symbol + " "))
        }
        if target.eq != "==" {
            replacements.append((" \(target.eq) ", " \(OP.eq.symbol) "))
        }
        if target.neq != "!=" {
            replacements.append((" \(target.neq) ", " \(OP.neq.symbol) "))
        }
        if target.lte != "<=" {
            replacements.append((" \(target.lte) ", " \(OP.lte.symbol) "))
        }
        if target.gte != ">=" {
            replacements.append((" \(target.gte) ", " \(OP.gte.symbol) "))
        }
        if target.mod != "%" {
            replacements.append((" \(target.mod) ", " \(OP.mod.symbol) "))
        }

        return replacements
    }
}
