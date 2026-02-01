<div> <img src="https://github.com/user-attachments/assets/766f0f42-33dc-4b47-bc22-0f31aae37b5f" width="192" alt="BattleScript JibberJabber JibJab JJ AI first programming language experiment GUI Icon">
<div>——  BattleScript.app  ——</div>
</div>

## JJ aka JibberJabber AI programming language 1.0 by Todd Bruss

An **AI-first programming language** created by [Todd Bruss](https://github.com/SuperBox64). JibberJabber is a polyglot engine designed to integrate AI models as primary execution components rather than external tools. It supports transcoding and cross-compilation across multiple environments, bridging high-level AI logic and system performance.

```jj
~>frob{7a3}::emit("Greetings Earthling!")
```

---

## What It Does

JibberJabber facilitates seamless interaction between human-written code and AI-generated logic. AI generates high-level JJ logic, and the engine materializes it into production-ready code for a specific tech stack.

- **10-Language Transcoding** - Write once, deploy to Swift, Python, C, C++, Go, JavaScript, and more
- **Run and Compile** - Beyond simple translation, JJ provides tooling to compile and run generated code in each target
- **Native ARM64 Compiler** - Generates Mach-O binaries directly, no assembler or linker needed
- **Agentic Engineering** - AI as a primary execution component, not an external tool

**Targets:** `py` `js` `c` `cpp` `swift` `objc` `objcpp` `go` `asm` `applescript`

---

## Prerequisites

```bash
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install go
brew install quickjs
```

See [jibjab/README.md](jibjab/README.md) for alternative install methods.

---

## Runtimes

| Runtime | Language | Location | Best For |
|---------|----------|----------|----------|
| **jjswift** | Swift | `jibjab/jjswift/` | Native macOS, ARM64 compilation |
| **jjpy** | Python | `jibjab/jjpy/` | Cross-platform |
| **BattleScript** | SwiftUI | `BattleScript/` | Visual IDE for JibJab |

See [jibjab/README.md](jibjab/README.md) for dependencies and setup.

---

## BattleScript IDE

Native macOS IDE for JibJab. Write JJ code and instantly see it transpiled to all 10 targets, then compile and run any target with one click.

<p align="left">
  <img src="https://github.com/user-attachments/assets/784f9205-34e3-4eea-a1d8-8eeee5e8c2c6" width="738" alt="BattleScript Experimental JibberJabber JibJab JJ Swift JJSwift IDE for macOS 14, 15, 26">
</p>

See [BattleScript/README.md](BattleScript/README.md) for details.

---

## CLI Usage

```
$ jjswift
JibJab Language v1.0 (Swift)
Usage:
  jjswift run <file.jj>                - Run JJ program (interpreter)
  jjswift compile <file.jj> [output]   - Compile direct to native binary
  jjswift asm <file.jj> [output]       - Compile via asm transpiler + as/ld
  jjswift transpile <file.jj> <target> - Transpile to target language
  jjswift build <file.jj> <target> [output] - Transpile + compile
  jjswift exec <file.jj> <target>      - Transpile + compile + run

Targets: applescript, asm, c, cpp, go, js, objc, objcpp, py, swift
```

```bash
$ jjswift exec examples/hello.jj py
Hello, JibJab World!

$ jjswift exec examples/hello.jj swift
Hello, JibJab World!

$ jjswift compile examples/hello.jj hello && ./hello
Hello, JibJab World!
```

---

## How It Works

```
JJ Source → Lexer → Parser → AST
                                 ├─ Interpreter → Run
                                 ├─ Compiler → ARM64 Mach-O → Run
                                 └─ Transpiler → 10 Languages → Compile → Run
```

See [Language Spec](jibjab/SPEC.md) for the full pipeline diagram.

---

## More

- [Quick Start & Commands (jjswift)](jibjab/README.md)
- [jjpy Runtime & Usage](jibjab/jjpy/README.md)
- [JJ Language Spec](jibjab/SPEC.md)
- [Regression Tests](jibjab/TESTS.md)
- [BattleScript SwiftUI JJ Experimental IDE](BattleScript/README.md)

---

## About JJ

JJ is an experimental AI-first computer programming language by Todd Bruss with a write once, run anywhere methodology. MIT License.
