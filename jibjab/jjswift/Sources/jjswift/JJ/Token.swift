/// JibJab Token Types and Token structure

enum TokenType {
    // Keywords
    case print      // ~>frob{7a3}
    case input      // ~>slurp{9f2}
    case loop       // <~loop{...}>>
    case when       // <~when{...}>>
    case `else`     // <~else>>
    case morph      // <~morph{...}>>
    case yeet       // ~>yeet{...}
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

struct Token {
    let type: TokenType
    let value: Any?
    let line: Int
    let col: Int
}
