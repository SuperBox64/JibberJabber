/// JibJab AST - Abstract Syntax Tree node definitions
/// Schema: ../../../common/ast.json

public protocol ASTNode {}

public struct Program: ASTNode {
    public let statements: [ASTNode]
}

public struct PrintStmt: ASTNode {
    public let expr: ASTNode
}

public struct InputExpr: ASTNode {
    public let prompt: ASTNode
}

public struct VarDecl: ASTNode {
    public let name: String
    public let value: ASTNode
}

public struct VarRef: ASTNode {
    public let name: String
}

public struct Literal: ASTNode {
    public let value: Any?
    public let numericType: NumericType?

    public init(value: Any?, numericType: NumericType? = nil) {
        self.value = value
        self.numericType = numericType
    }
}

public enum NumericType: String {
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

public struct BinaryOp: ASTNode {
    public let left: ASTNode
    public let op: String
    public let right: ASTNode
}

public struct UnaryOp: ASTNode {
    public let op: String
    public let operand: ASTNode
}

public struct LoopStmt: ASTNode {
    public let `var`: String
    public let start: ASTNode?
    public let end: ASTNode?
    public let collection: ASTNode?
    public let condition: ASTNode?
    public let body: [ASTNode]
}

public struct IfStmt: ASTNode {
    public let condition: ASTNode
    public let thenBody: [ASTNode]
    public let elseBody: [ASTNode]?
}

public struct FuncDef: ASTNode {
    public let name: String
    public let params: [String]
    public let body: [ASTNode]
}

public struct FuncCall: ASTNode {
    public let name: String
    public let args: [ASTNode]
}

public struct ReturnStmt: ASTNode {
    public let value: ASTNode
}

public struct ThrowStmt: ASTNode {
    public let value: ASTNode
}

public struct EnumDef: ASTNode {
    public let name: String
    public let cases: [String]
}

public struct ArrayLiteral: ASTNode {
    public let elements: [ASTNode]
}

public struct DictLiteral: ASTNode {
    public let pairs: [(key: ASTNode, value: ASTNode)]
}

public struct TupleLiteral: ASTNode {
    public let elements: [ASTNode]
}

public struct IndexAccess: ASTNode {
    public let array: ASTNode
    public let index: ASTNode
}

public enum StringInterpPart {
    case literal(String)
    case variable(String)
}

public struct StringInterpolation: ASTNode {
    public let parts: [StringInterpPart]
}

public struct TryStmt: ASTNode {
    public let tryBody: [ASTNode]
    public let oopsBody: [ASTNode]?
    public let oopsVar: String?
}

public struct CommentNode: ASTNode {
    public let text: String
}
