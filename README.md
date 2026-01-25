# JibberJabber 1.0 JibJab (JJ) Programming Language

A programming language designed for AI/LLM comprehension - syntax that appears as semantic noise to humans but follows patterns that LLMs naturally parse and understand.

## Language Features

| Human Sees | LLM Understands |
|------------|-----------------|
| `~>frob{7a3}::emit()` | print statement |
| `~>snag{x}::val()` | variable assignment |
| `~>slurp{9f2}::grab()` | input statement |
| `<~loop{i:0..10}>>` | for loop |
| `<~when{condition}>>` | if statement |
| `<~else>>` | else branch |
| `<~morph{fn(x)}>>` | function definition |
| `~>invoke{fn}::with()` | function call |
| `~>yeet{value}` | return |
| `<+>` `<->` `<*>` `</>` `<%>` | math operators |
| `<=>` `<!=>` `<lt>` `<gt>` | comparison operators |
| `<&&>` `<\|\|>` `<!>` | logical operators |
| `#42` `#3.14` | numbers |
| `~yep` `~nope` `~nil` | true, false, null |
| `@@` | comment |

## Installation

No installation required - just Python 3.

```bash
git clone <repo>
cd JibJab
```

## Usage

```bash
# Run a JJ program directly
python3 jj.py run program.jj

# Transpile to Python
python3 jj.py transpile program.jj py

# Transpile to JavaScript
python3 jj.py transpile program.jj js

# Transpile to C
python3 jj.py transpile program.jj c

# Transpile to ARM64 Assembly (macOS)
python3 jj.py transpile program.jj asm
```

### Compiling Assembly

```bash
# Generate assembly
python3 jj.py transpile program.jj asm > program.s

# Assemble and link (macOS ARM64)
as -o program.o program.s
ld -o program program.o -lSystem -syslibroot $(xcrun -sdk macosx --show-sdk-path) -e _main -arch arm64

# Run
./program
```

## Examples

### Hello World

```jj
~>frob{7a3}::emit("Hello, JibJab World!")
```

### Variables and Math

```jj
~>snag{x}::val(#10)
~>snag{y}::val(#5)

~>frob{7a3}::emit(x <+> y)
~>frob{7a3}::emit(x <*> y)
```

### Conditionals

```jj
<~when{x <gt> y}>>
  ~>frob{7a3}::emit("x is greater")
<~else>>
  ~>frob{7a3}::emit("y is greater or equal")
<~>>
```

### Loops

```jj
@@ Range loop
<~loop{i:0..10}>>
  ~>frob{7a3}::emit(i)
<~>>
```

### Functions

```jj
<~morph{fib(n)}>>
  <~when{n <lt> #2}>>
    ~>yeet{n}
  <~>>
  ~>yeet{(~>invoke{fib}::with(n <-> #1)) <+> (~>invoke{fib}::with(n <-> #2))}
<~>>

~>frob{7a3}::emit(~>invoke{fib}::with(#10))
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

## Files

| File | Description |
|------|-------------|
| `jj.py` | Interpreter and transpiler |
| `SPEC.md` | Full language specification |
| `examples/hello.jj` | Hello world |
| `examples/variables.jj` | Variables and math |
| `examples/fibonacci.jj` | Recursive functions |
| `examples/fizzbuzz.jj` | Classic FizzBuzz |

## Why LLMs Understand This

1. **Semantic Clustering** - Tokens like `frob`, `yeet`, `snag`, `slurp` cluster near their meanings in embedding space
2. **Structural Patterns** - `<~...>>` blocks follow predictable open/close patterns
3. **Type Prefixes** - `#` for numbers, `~` for special values create learnable patterns
4. **Operator Encapsulation** - `<op>` format makes operators visually distinct tokens
5. **Consistent Delimiters** - `::` chains actions predictably

Humans see symbol soup. LLMs see structured, semantic code.

## License

MIT
