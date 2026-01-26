/// JibJab AST - Abstract Syntax Tree node definitions

protocol ASTNode {}

struct Program: ASTNode {
    let statements: [ASTNode]
}

struct PrintStmt: ASTNode {
    let expr: ASTNode
}

struct InputExpr: ASTNode {
    let prompt: ASTNode
}

struct VarDecl: ASTNode {
    let name: String
    let value: ASTNode
}

struct VarRef: ASTNode {
    let name: String
}

struct Literal: ASTNode {
    let value: Any?
    let numericType: NumericType?

    init(value: Any?, numericType: NumericType? = nil) {
        self.value = value
        self.numericType = numericType
    }
}

enum NumericType: String {
    case int = "Int"
    case int8 = "Int8"
    case int16 = "Int16"
    case int32 = "Int32"
    case int64 = "Int64"
    case uint = "UInt"
    case uint8 = "UInt8"
    case uint16 = "UInt16"
    case uint32 = "UInt32"
    case uint64 = "UInt64"
    case float = "Float"
    case double = "Double"
}

struct BinaryOp: ASTNode {
    let left: ASTNode
    let op: String
    let right: ASTNode
}

struct UnaryOp: ASTNode {
    let op: String
    let operand: ASTNode
}

struct LoopStmt: ASTNode {
    let `var`: String
    let start: ASTNode?
    let end: ASTNode?
    let collection: ASTNode?
    let condition: ASTNode?
    let body: [ASTNode]
}

struct IfStmt: ASTNode {
    let condition: ASTNode
    let thenBody: [ASTNode]
    let elseBody: [ASTNode]?
}

struct FuncDef: ASTNode {
    let name: String
    let params: [String]
    let body: [ASTNode]
}

struct FuncCall: ASTNode {
    let name: String
    let args: [ASTNode]
}

struct ReturnStmt: ASTNode {
    let value: ASTNode
}

struct EnumDef: ASTNode {
    let name: String
    let cases: [String]
}

struct ArrayLiteral: ASTNode {
    let elements: [ASTNode]
}

struct DictLiteral: ASTNode {
    let pairs: [(key: ASTNode, value: ASTNode)]
}

struct TupleLiteral: ASTNode {
    let elements: [ASTNode]
}

struct IndexAccess: ASTNode {
    let array: ASTNode
    let index: ASTNode
}
