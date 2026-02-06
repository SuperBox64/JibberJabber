# Fixes to Potential Issues

## Stack Overflow in Transpiler `expr()` Methods (Background Threads)

**Status:** Mitigated (not fully resolved)

**Problem:** BattleScript crashes with `___chkstk_darwin` (stack overflow) when transpiling complex JJ programs like fizzbuzz on background threads. The recursive `expr()` method in transpilers overflows the default 512KB stack of `DispatchQueue.global()` threads.

**Current Fix:** Changed `ContentView.swift` to use `Thread` with 8MB stack (matching main thread) instead of `DispatchQueue.global()` for transpilation and compile-and-run work.

**Proper Fix:** Convert recursive `expr()` and `stmtToString()` methods to iterative using an explicit stack with continuation-passing. This would make nesting depth limited by heap (gigabytes) instead of thread stack. Scope:

- 8 Swift transpilers have recursive `expr()`: Python, JavaScript, Swift, Go, CFamilyBase, Cpp, AppleScript, Assembly
- `stmtToString()` is also recursive through nested if/else/loop/try bodies
- `expr()` returns a `String`, requiring a result stack — not a simple loop rewrite
- AppleScript has mutual recursion (`expr` <-> `exprWithNumericConversion`)
- Assembly transpiler is 1,500+ lines with complex recursive structure
- All 390+ regression tests must still pass after refactor
