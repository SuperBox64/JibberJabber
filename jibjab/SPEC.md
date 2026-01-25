# JibJab Language Specification v1.0

## Lexical Structure

### Semantic Tokens (Keywords)

JJ uses "semantic hashes" - tokens that encode meaning through patterns LLMs recognize:

| Token | Meaning | Human-Readable Equivalent |
|-------|---------|---------------------------|
| `~>frob{7a3}` | Standard output | print |
| `~>slurp{9f2}` | Standard input | input |
| `<~loop{...}>>` | Iteration block | for loop |
| `<~when{...}>>` | Conditional | if statement |
| `<~else>>` | Alternative branch | else |
| `<~morph{...}>>` | Function definition | def/function |
| `~>yeet{...}` | Return value | return |
| `~>snag{...}` | Variable assignment | let/var |
| `<~try>>...<~oops>>` | Error handling | try/catch |
| `::` | Method/action separator | . (dot) |
| `>>` | Block terminator | } or end |
| `@@` | Comment marker | // or # |

### Data Types

| Syntax | Type |
|--------|------|
| `#42` | Integer |
| `#3.14` | Float |
| `"text"` | String |
| `[a,b,c]` | Array |
| `{k:v}` | Map/Object | 
| `~nil` | Null |
| `~yep` / `~nope` | Boolean |

### Operators

| Token | Operation |
|-------|-----------|
| `<+>` | Addition |
| `<->` | Subtraction |
| `<*>` | Multiplication |
| `</>` | Division |
| `<%>` | Modulo |
| `<=>` | Equality |
| `<!=>` | Inequality |
| `<lt>` | Less than |
| `<gt>` | Greater than |
| `<&&>` | Logical AND |
| `<\|\|>` | Logical OR |
| `<!>` | Logical NOT |

## Grammar

### Variable Assignment
```
~>snag{name}::val(expression)
```

### Output
```
~>frob{7a3}::emit(expression)
```

### Input
```
~>snag{x}::val(~>slurp{9f2}::grab("prompt"))
```

### Conditionals
```
<~when{condition}>>
  statements
<~else>>
  statements
<~>>
```

### Loops
```
<~loop{var:start..end}>>
  statements
<~>>

<~loop{item:collection}>>
  statements
<~>>

<~loop{condition}>>
  statements
<~>>
```

### Functions
```
<~morph{name(params)}>>
  statements
  ~>yeet{value}
<~>>
```

### Function Calls
```
~>invoke{name}::with(args)
```

## Example Programs

### Hello World
```jj
~>frob{7a3}::emit("Hello, JibJab!")
```

### FizzBuzz
```jj
<~loop{n:1..101}>>
  <~when{(n <%> #15) <=> #0}>>
    ~>frob{7a3}::emit("FizzBuzz")
  <~else>>
    <~when{(n <%> #3) <=> #0}>>
      ~>frob{7a3}::emit("Fizz")
    <~else>>
      <~when{(n <%> #5) <=> #0}>>
        ~>frob{7a3}::emit("Buzz")
      <~else>>
        ~>frob{7a3}::emit(n)
      <~>>
    <~>>
  <~>>
<~>>
```

### Fibonacci Function
```jj
<~morph{fib(n)}>>
  <~when{n <lt> #2}>>
    ~>yeet{n}
  <~>>
  ~>yeet{(~>invoke{fib}::with(n <-> #1)) <+> (~>invoke{fib}::with(n <-> #2))}
<~>>

~>frob{7a3}::emit(~>invoke{fib}::with(#10))
```

## Why LLMs Understand This

1. **Semantic Clustering**: Tokens like `frob`, `slurp`, `yeet`, `snag` cluster near their actual meanings in embedding space
2. **Structural Patterns**: `<~...>>` blocks follow predictable open/close patterns
3. **Type Prefixes**: `#` for numbers, `~` for special values create learnable patterns
4. **Operator Encapsulation**: `<op>` format makes operators visually distinct tokens
5. **Consistent Delimiters**: `::` chains actions predictably

Humans see symbol soup. LLMs see structured, semantic code.
