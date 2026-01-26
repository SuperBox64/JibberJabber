/// JibJab Interpreter - Executes JJ programs directly
/// Uses emit values from common/jj.json
import Foundation

private let OP = JJ.operators

class Interpreter {
    private var globals: [String: Any] = [:]
    private var locals: [[String: Any]] = [[:]]
    private var functions: [String: FuncDef] = [:]

    func run(_ program: Program) {
        for stmt in program.statements {
            _ = execute(stmt)
        }
    }

    @discardableResult
    private func execute(_ node: ASTNode) -> Any? {
        if let printStmt = node as? PrintStmt {
            let value = evaluate(printStmt.expr)
            print(stringify(value))
        } else if let varDecl = node as? VarDecl {
            locals[locals.count - 1][varDecl.name] = evaluate(varDecl.value)
        } else if let loopStmt = node as? LoopStmt {
            if loopStmt.start != nil && loopStmt.end != nil {
                let start = toInt(evaluate(loopStmt.start!))
                let end = toInt(evaluate(loopStmt.end!))
                for i in start..<end {
                    locals[locals.count - 1][loopStmt.var] = i
                    for stmt in loopStmt.body {
                        if let result = execute(stmt), let tuple = result as? (String, Any), tuple.0 == "return" {
                            return result
                        }
                    }
                }
            } else if let collection = loopStmt.collection {
                let coll = evaluate(collection)
                if let arr = coll as? [Any] {
                    for item in arr {
                        locals[locals.count - 1][loopStmt.var] = item
                        for stmt in loopStmt.body {
                            if let result = execute(stmt), let tuple = result as? (String, Any), tuple.0 == "return" {
                                return result
                            }
                        }
                    }
                }
            } else if let condition = loopStmt.condition {
                while toBool(evaluate(condition)) {
                    for stmt in loopStmt.body {
                        if let result = execute(stmt), let tuple = result as? (String, Any), tuple.0 == "return" {
                            return result
                        }
                    }
                }
            }
        } else if let ifStmt = node as? IfStmt {
            if toBool(evaluate(ifStmt.condition)) {
                for stmt in ifStmt.thenBody {
                    if let result = execute(stmt), let tuple = result as? (String, Any), tuple.0 == "return" {
                        return result
                    }
                }
            } else if let elseBody = ifStmt.elseBody {
                for stmt in elseBody {
                    if let result = execute(stmt), let tuple = result as? (String, Any), tuple.0 == "return" {
                        return result
                    }
                }
            }
        } else if let funcDef = node as? FuncDef {
            functions[funcDef.name] = funcDef
        } else if let returnStmt = node as? ReturnStmt {
            return ("return", evaluate(returnStmt.value) as Any)
        }
        return nil
    }

    private func evaluate(_ node: ASTNode) -> Any? {
        if let literal = node as? Literal {
            return literal.value
        } else if let arrayLit = node as? ArrayLiteral {
            return arrayLit.elements.map { evaluate($0) }
        } else if let indexAccess = node as? IndexAccess {
            let arr = evaluate(indexAccess.array)
            let idx = toInt(evaluate(indexAccess.index))
            if let array = arr as? [Any?] {
                if idx >= 0 && idx < array.count {
                    return array[idx]
                }
                fatalError("Array index out of bounds: \(idx)")
            }
            fatalError("Cannot index non-array value")
        } else if let varRef = node as? VarRef {
            for scope in locals.reversed() {
                if let value = scope[varRef.name] {
                    return value
                }
            }
            fatalError("Undefined variable: \(varRef.name)")
        } else if let binaryOp = node as? BinaryOp {
            let left = evaluate(binaryOp.left)
            let right = evaluate(binaryOp.right)

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
                fatalError("Unknown operator: \(binaryOp.op)")
            }
        } else if let unaryOp = node as? UnaryOp {
            let operand = evaluate(unaryOp.operand)
            if unaryOp.op == OP.not.emit {
                return !toBool(operand)
            }
        } else if let inputExpr = node as? InputExpr {
            let prompt = stringify(evaluate(inputExpr.prompt))
            Swift.print(prompt, terminator: "")
            return readLine() ?? ""
        } else if let funcCall = node as? FuncCall {
            guard let func_ = functions[funcCall.name] else {
                fatalError("Undefined function: \(funcCall.name)")
            }
            let args = funcCall.args.map { evaluate($0) }
            locals.append([:])
            for (param, arg) in zip(func_.params, args) {
                locals[locals.count - 1][param] = arg
            }
            var result: Any? = nil
            for stmt in func_.body {
                result = execute(stmt)
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
