<p align="center">
  <img src="battlescript.png" width="256" alt="BattleScript Icon">
</p>

# JibberJabber (JJ) 1.0

An **AI-first programming language** created by [Todd Bruss](https://github.com/SuperBox64). JibberJabber is a polyglot engine designed to integrate AI models as primary execution components rather than external tools. It supports transcoding and cross-compilation across multiple environments, bridging high-level AI logic and system performance.

```jj
~>frob{7a3}::emit("Greetings Earthling!")
```

---

## What It Does

- **10-Language Transcoding** - Write JJ once, transpile to 10 target languages
- **Run and Compile** - Transpile, compile, and execute generated code in each target
- **Native ARM64 Compiler** - Generates Mach-O binaries directly, no assembler or linker needed
- **Agentic Engineering** - AI generates JJ logic, the engine materializes it into production-ready code for any target

**Targets:** `py` `js` `c` `cpp` `swift` `objc` `objcpp` `go` `asm` `applescript`

---

## Runtimes

| Runtime | Language | Location | Best For |
|---------|----------|----------|----------|
| **jjswift** | Swift | `jibjab/jjswift/` | Native macOS, ARM64 compilation |
| **jjpy** | Python | `jibjab/jjpy/` | Cross-platform |
| **BattleScript** | SwiftUI | `BattleScript/` | Visual IDE for JibJab |

See [jibjab/README.md](jibjab/README.md) for quick start, commands, and dependencies.

---

## BattleScript IDE

Native macOS IDE for JibJab. Write JJ code and instantly see it transpiled to all 10 targets, then compile and run any target with one click.

<p align="center">
  <img src="battlescript-ide-prerelease.png" width="700" alt="BattleScript IDE">
</p>

See [BattleScript/README.md](BattleScript/README.md) for details.

---

## How It Works

```
JJ Source → Lexer → Parser → AST
                                 ├─ Interpret → Output
                                 ├─ Native Compile → ARM64 Mach-O → Run
                                 └─ Transpile → 10 Languages → Compile → Run
```

See [Language Spec](jibjab/SPEC.md) for the full pipeline diagram.

---

## More

- [Quick Start & Commands](jibjab/README.md)
- [Language Spec](jibjab/SPEC.md)
- [Regression Tests](jibjab/TESTS.md)
- [BattleScript IDE](BattleScript/README.md)

---

## License

MIT

---

*JibJab: Where humans see noise and AI sees code.*
