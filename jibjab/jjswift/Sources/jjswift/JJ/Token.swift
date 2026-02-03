/// JibJab Token Types and Token structure

public enum TokenType {
    // Keywords
    case print      // ~>frob{7a3}
    case log        // ~>spew{b4d}
    case const      // ~>grip{f1x}
    case input      // ~>slurp{9f2}
    case loop       // <~loop{...}>>
    case when       // <~when{...}>>
    case `else`     // <~else>>
    case morph      // <~morph{...}>>
    case yeet       // ~>yeet{...}
    case kaboom     // ~>kaboom{...}
    case snag       // ~>snag{...}
    case invoke     // ~>invoke{...}
    case `enum`     // ~>enum{...}
    case `try`      // <~try>>
    case oops       // <~oops>>
    case blockEnd   // <~>>

    // Operators
    case add        // <+>
    case sub        // <->
    case mul        // <*>
    case div        // </>
    case mod        // <%>
    case eq         // <=>
    case neq        // <!=>
    case lt         // <lt>
    case lte        // <lte>
    case gt         // <gt>
    case gte        // <gte>
    case and        // <&&>
    case or         // <||>
    case not        // <!>

    // Literals
    case number     // #42 or #3.14
    case string     // "..."
    case interpString // "...{var}..." string with interpolation
    case array      // [...]
    case map        // {...}
    case `nil`      // ~nil
    case `true`     // ~yep
    case `false`    // ~nope

    // Structure
    case action     // ::
    case emit       // emit
    case grab       // grab
    case val        // val
    case with       // with
    case cases      // cases
    case range      // ..
    case colon      // :
    case lparen     // (
    case rparen     // )
    case lbracket   // [
    case rbracket   // ]
    case lbrace     // {
    case rbrace     // }
    case comma      // ,

    // Other
    case identifier
    case comment    // @@
    case newline
    case eof
}

public struct Token {
    public let type: TokenType
    public let value: Any?
    public let line: Int
    public let col: Int
    public let numericType: String?

    public init(type: TokenType, value: Any?, line: Int, col: Int, numericType: String? = nil) {
        self.type = type
        self.value = value
        self.line = line
        self.col = col
        self.numericType = numericType
    }
}
