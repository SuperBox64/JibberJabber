<p align="center">
  <img src="../battlescript.png" width="128" alt="BattleScript Icon">
</p>

# BattleScript

A native macOS IDE for the JibJab programming language. Write JJ code and instantly see it transpiled to 10 target languages, then compile and run any target with one click.

---

## Features

- **Live Transpilation** - JJ source is transpiled to all targets in real-time as you type
- **11 Language Tabs** - JJ, Python, JavaScript, C, C++, Swift, Objective-C, Objective-C++, Go, ARM64 Assembly, AppleScript
- **One-Click Run** - Compile and execute any target language directly from the IDE
- **Built-in Examples** - Hello World, Variables, FizzBuzz, Fibonacci, Arrays, Comparisons, Dictionaries, Enums, Numbers, Tuples
- **Code Editor** - Monospaced editor with smart quote substitution disabled for clean code input

---

## Requirements

- macOS 14.0+
- Xcode 16.0+ (to build)
- Swift 5.9+

### Installing Dependencies

BattleScript can transpile and run code in 10 target languages. Some targets require external tools.

#### Required

```bash
# Xcode Command Line Tools (provides clang, swiftc, as, ld)
xcode-select --install
```

#### QuickJS (for JavaScript target)

[QuickJS](https://bellard.org/quickjs/) is a small, embeddable JavaScript engine used to compile and run transpiled JavaScript code.

```bash
brew install quickjs
```

This installs `qjs` (interpreter) and `qjsc` (compiler) to `/opt/homebrew/bin/`.

#### Go (for Go target)

[Go](https://go.dev) is used to compile and run transpiled Go code.

```bash
brew install go
```

This installs the `go` toolchain to `/opt/homebrew/bin/`.

#### Dependency Summary

| Target | Tool | Install |
|--------|------|---------|
| Python | `python3` | Pre-installed on macOS |
| JavaScript | `qjs` / `qjsc` | `brew install quickjs` |
| C / C++ | `clang` / `clang++` | `xcode-select --install` |
| Swift | `swiftc` | `xcode-select --install` |
| Objective-C / C++ | `clang` + Foundation | `xcode-select --install` |
| Go | `go` | `brew install go` |
| ARM64 Assembly | `as` + `ld` | `xcode-select --install` |
| AppleScript | `osascript` | Pre-installed on macOS |

### Startup Checks

BattleScript automatically checks for required dependencies on launch and displays an animated overlay showing the status of each tool:

- **Xcode Command Line Tools** (`clang`)
- **Go** (`go`)
- **QuickJS** (`qjsc`)

If all tools are found, the overlay auto-dismisses. If any are missing, install hints are shown with a dismiss button.

---

## Building

### From Xcode

Open `BattleScript.xcodeproj` in Xcode and build/run (Cmd+R).

### From the Command Line

```bash
cd BattleScript
xcodebuild -project BattleScript.xcodeproj -scheme BattleScript -configuration Debug build CONFIGURATION_BUILD_DIR=/tmp/BattleScriptBuild
open /tmp/BattleScriptBuild/BattleScript.app
```

---

## Architecture

BattleScript is a SwiftUI macOS app that links against `JJLib`, the core JibJab library from `jjswift`.

```
BattleScript/
├── BattleScript.xcodeproj
└── BattleScript/
    ├── BattleScriptApp.swift   # App entry point
    ├── ContentView.swift       # Main layout: sidebar + editor + output
    ├── EditorTabView.swift     # Tab bar and code editor (NSTextView-backed)
    ├── OutputView.swift        # Run output display
    └── JJEngine.swift          # Bridge to JJLib: parse, transpile, interpret, compile & run
```

### How It Works

1. **Edit** - Write JJ code in the JJ tab (or select a built-in example)
2. **Transpile** - `JJEngine` parses the JJ source and transpiles to all 10 targets in real-time
3. **Browse** - Click any language tab to view the transpiled output
4. **Run** - Click the Run button to compile and execute the selected target
   - **JJ tab**: Runs via the built-in interpreter
   - **Other tabs**: Writes transpiled code to `/tmp`, compiles with the target's toolchain, and captures the output

### Dependencies

BattleScript uses `jjswift` as a local Swift Package Manager dependency. The `JJLib` library target provides the lexer, parser, AST, interpreter, and all transpilers.

---

## See Also

- [Main README](../README.md) - JibberJabber project overview
- [jibjab/README.md](../jibjab/README.md) - CLI implementation details
- [jibjab/SPEC.md](../jibjab/SPEC.md) - JibJab language specification
