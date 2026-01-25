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

struct ArrayLiteral: ASTNode {
    let elements: [ASTNode]
}
