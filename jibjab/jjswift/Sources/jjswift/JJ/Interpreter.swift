/// JibJab Interpreter - Executes JJ programs directly
/// Uses emit values from common/jj.json
import Foundation

private let OP = JJ.operators

public enum RuntimeError: Error, CustomStringConvertible {
    case error(String)
    public var description: String {
        switch self { case .error(let msg): return msg }
    }
}

public class Interpreter {
    private var globals: [String: Any] = [:]
    private var locals: [[String: Any]] = [[:]]
    private var functions: [String: FuncDef] = [:]

    public init() {}

    public func run(_ program: Program) throws {
        for stmt in program.statements {
            _ = try execute(stmt)
        }
    }

    @discardableResult
    private func execute(_ node: ASTNode) throws -> Any? {
        if let printStmt = node as? PrintStmt {
            let value = try evaluate(printStmt.expr)
            print(stringify(value))
        } else if let varDecl = node as? VarDecl {
            locals[locals.count - 1][varDecl.name] = try evaluate(varDecl.value)
        } else if let loopStmt = node as? LoopStmt {
            if let startNode = loopStmt.start, let endNode = loopStmt.end {
                let start = toInt(try evaluate(startNode))
                let end = toInt(try evaluate(endNode))
                for i in start..<end {
                    locals[locals.count - 1][loopStmt.var] = i
                    for stmt in loopStmt.body {
                        if let result = try execute(stmt), let tuple = result as? (String, Any), tuple.0 == "return" {
                            return result
                        }
                    }
                }
            } else if let collection = loopStmt.collection {
                let coll = try evaluate(collection)
                if let arr = coll as? [Any] {
                    for item in arr {
                        locals[locals.count - 1][loopStmt.var] = item
                        for stmt in loopStmt.body {
                            if let result = try execute(stmt), let tuple = result as? (String, Any), tuple.0 == "return" {
                                return result
                            }
                        }
                    }
                }
            } else if let condition = loopStmt.condition {
                while toBool(try evaluate(condition)) {
                    for stmt in loopStmt.body {
                        if let result = try execute(stmt), let tuple = result as? (String, Any), tuple.0 == "return" {
                            return result
                        }
                    }
                }
            }
        } else if let ifStmt = node as? IfStmt {
            if toBool(try evaluate(ifStmt.condition)) {
                for stmt in ifStmt.thenBody {
                    if let result = try execute(stmt), let tuple = result as? (String, Any), tuple.0 == "return" {
                        return result
                    }
                }
            } else if let elseBody = ifStmt.elseBody {
                for stmt in elseBody {
                    if let result = try execute(stmt), let tuple = result as? (String, Any), tuple.0 == "return" {
                        return result
                    }
                }
            }
        } else if let funcDef = node as? FuncDef {
            functions[funcDef.name] = funcDef
        } else if let enumDef = node as? EnumDef {
            // Store enum as a dictionary mapping case names to themselves
            var enumDict: [String: Any?] = [:]
            for caseName in enumDef.cases {
                enumDict[caseName] = caseName
            }
            locals[locals.count - 1][enumDef.name] = enumDict
        } else if let returnStmt = node as? ReturnStmt {
            return ("return", try evaluate(returnStmt.value) as Any)
        }
        return nil
    }

    private func evaluate(_ node: ASTNode) throws -> Any? {
        if let literal = node as? Literal {
            return literal.value
        } else if let arrayLit = node as? ArrayLiteral {
            return try arrayLit.elements.map { try evaluate($0) }
        } else if let dictLit = node as? DictLiteral {
            var dict: [String: Any?] = [:]
            for pair in dictLit.pairs {
                let key = stringify(try evaluate(pair.key))
                let value = try evaluate(pair.value)
                dict[key] = value
            }
            return dict
        } else if let tupleLit = node as? TupleLiteral {
            // Return tuple as a special wrapper to distinguish from arrays
            return ("tuple", try tupleLit.elements.map { try evaluate($0) })
        } else if let indexAccess = node as? IndexAccess {
            let container = try evaluate(indexAccess.array)
            let key = try evaluate(indexAccess.index)
            if let array = container as? [Any?] {
                let idx = toInt(key)
                if idx >= 0 && idx < array.count {
                    return array[idx]
                }
                throw RuntimeError.error("Array index out of bounds: \(idx)")
            }
            if let tuple = container as? (String, [Any?]), tuple.0 == "tuple" {
                let idx = toInt(key)
                if idx >= 0 && idx < tuple.1.count {
                    return tuple.1[idx]
                }
                throw RuntimeError.error("Tuple index out of bounds: \(idx)")
            }
            if let dict = container as? [String: Any?] {
                let keyStr = stringify(key)
                if let value = dict[keyStr] {
                    return value
                }
                throw RuntimeError.error("Dictionary key not found: \(keyStr)")
            }
            throw RuntimeError.error("Cannot index non-array/non-tuple/non-dictionary value")
        } else if let varRef = node as? VarRef {
            for scope in locals.reversed() {
                if let value = scope[varRef.name] {
                    return value
                }
            }
            throw RuntimeError.error("Undefined variable: \(varRef.name)")
        } else if let binaryOp = node as? BinaryOp {
            let left = try evaluate(binaryOp.left)
            let right = try evaluate(binaryOp.right)

            switch binaryOp.op {
            case let op where op == OP.add.emit:
                if let l = left as? Int, let r = right as? Int { return l + r }
                if let l = left as? Double, let r = right as? Double { return l + r }
                if let l = left as? Int, let r = right as? Double { return Double(l) + r }
                if let l = left as? Double, let r = right as? Int { return l + Double(r) }
                if let l = left as? String, let r = right as? String { return l + r }
                return stringify(left) + stringify(right)
            case let op where op == OP.sub.emit:
                return toDouble(left) - toDouble(right)
            case let op where op == OP.mul.emit:
                return toDouble(left) * toDouble(right)
            case let op where op == OP.div.emit:
                return toDouble(left) / toDouble(right)
            case let op where op == OP.mod.emit:
                return toInt(left) % toInt(right)
            case let op where op == OP.eq.emit:
                return isEqual(left, right)
            case let op where op == OP.neq.emit:
                return !isEqual(left, right)
            case let op where op == OP.lt.emit:
                return toDouble(left) < toDouble(right)
            case let op where op == OP.lte.emit:
                return toDouble(left) <= toDouble(right)
            case let op where op == OP.gt.emit:
                return toDouble(left) > toDouble(right)
            case let op where op == OP.gte.emit:
                return toDouble(left) >= toDouble(right)
            case let op where op == OP.and.emit:
                return toBool(left) && toBool(right)
            case let op where op == OP.or.emit:
                return toBool(left) || toBool(right)
            default:
                throw RuntimeError.error("Unknown operator: \(binaryOp.op)")
            }
        } else if let unaryOp = node as? UnaryOp {
            let operand = try evaluate(unaryOp.operand)
            if unaryOp.op == OP.not.emit {
                return !toBool(operand)
            }
        } else if let inputExpr = node as? InputExpr {
            let prompt = stringify(try evaluate(inputExpr.prompt))
            Swift.print(prompt, terminator: "")
            return readLine() ?? ""
        } else if let funcCall = node as? FuncCall {
            guard let func_ = functions[funcCall.name] else {
                throw RuntimeError.error("Undefined function: \(funcCall.name)")
            }
            let args = try funcCall.args.map { try evaluate($0) }
            locals.append([:])
            for (param, arg) in zip(func_.params, args) {
                locals[locals.count - 1][param] = arg
            }
            var result: Any? = nil
            for stmt in func_.body {
                result = try execute(stmt)
                if let tuple = result as? (String, Any), tuple.0 == "return" {
                    locals.removeLast()
                    return tuple.1
                }
            }
            locals.removeLast()
            return result
        }
        return nil
    }

    private func stringify(_ value: Any?) -> String {
        guard let value = value else { return "nil" }
        if let str = value as? String { return str }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let int = value as? Int { return String(int) }
        if let double = value as? Double {
            if double == Double(Int(double)) {
                return String(Int(double))
            }
            return String(double)
        }
        if let arr = value as? [Any?] {
            let items = arr.map { stringify($0) }
            return "[" + items.joined(separator: ", ") + "]"
        }
        if let tuple = value as? (String, [Any?]), tuple.0 == "tuple" {
            let items = tuple.1.map { stringify($0) }
            return "(" + items.joined(separator: ", ") + ")"
        }
        if let dict = value as? [String: Any?] {
            let items = dict.map { "\"\($0.key)\": \(stringify($0.value))" }
            return "{" + items.joined(separator: ", ") + "}"
        }
        return String(describing: value)
    }

    private func toInt(_ value: Any?) -> Int {
        guard let value = value else { return 0 }
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let str = value as? String { return Int(str) ?? 0 }
        return 0
    }

    private func toDouble(_ value: Any?) -> Double {
        guard let value = value else { return 0.0 }
        if let int = value as? Int { return Double(int) }
        if let double = value as? Double { return double }
        if let str = value as? String { return Double(str) ?? 0.0 }
        return 0.0
    }

    private func toBool(_ value: Any?) -> Bool {
        guard let value = value else { return false }
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let double = value as? Double { return double != 0.0 }
        if let str = value as? String { return !str.isEmpty }
        return true
    }

    private func isEqual(_ left: Any?, _ right: Any?) -> Bool {
        if left == nil && right == nil { return true }
        if left == nil || right == nil { return false }
        if let l = left as? Int, let r = right as? Int { return l == r }
        if let l = left as? Double, let r = right as? Double { return l == r }
        if let l = left as? String, let r = right as? String { return l == r }
        if let l = left as? Bool, let r = right as? Bool { return l == r }
        return false
    }
}
