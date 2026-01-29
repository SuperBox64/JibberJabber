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

### Optional (for running transpiled targets)

| Target | Requirement |
|--------|-------------|
| Python | `python3` (pre-installed on macOS) |
| JavaScript | `qjsc` / `qjs` (`brew install quickjs`) |
| C / C++ | `clang` / `clang++` (Xcode Command Line Tools) |
| Swift | `swiftc` (Xcode Command Line Tools) |
| Objective-C / C++ | `clang` + Foundation framework |
| Go | `go` (`brew install go`) |
| ARM64 Assembly | `as` + `ld` (Xcode Command Line Tools) |
| AppleScript | `osacompile` / `osascript` (pre-installed on macOS) |

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
