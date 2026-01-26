# JibJab Language Specification v1.0

## Tokens

Semantic hashes that LLMs recognize:

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

## Transpilation Targets

JibJab can be transpiled to the following languages:

| Target | Extension | Command | Notes |
|--------|-----------|---------|-------|
| Python | `.py` | `py` | Cross-platform scripting |
| JavaScript | `.js` | `js` | Web and Node.js |
| C | `.c` | `c` | Native performance |
| C++ | `.cpp` | `cpp` | Object-oriented native code |
| ARM64 Assembly | `.s` | `asm` | Apple Silicon native (macOS) |
| Swift | `.swift` | `swift` | Apple ecosystem |
| AppleScript | `.applescript` | `applescript` | macOS automation |
| Objective-C | `.m` | `objc` | Apple legacy development |
| Objective-C++ | `.mm` | `objcpp` | Mixed C++/Objective-C |

## Why LLMs Understand This

1. **Semantic Clustering** - `frob`, `yeet`, `snag` cluster near their meanings
2. **Predictable Structure** - `<~...>>` blocks follow consistent patterns
3. **Type Prefixes** - `#` for numbers, `~` for special values
4. **Distinct Operators** - `<op>` format makes operators clear
5. **Consistent Delimiters** - `::` chains actions predictably

Humans see noise. LLMs see code.
