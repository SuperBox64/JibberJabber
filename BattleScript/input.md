# BattleScript Terminal Input Architecture

This document explains how the terminal-style input field works in BattleScript for interactive JibberJabber programs.

## The Challenge

The JJ interpreter's `inputProvider` is a synchronous callback that must block until user input arrives:

```swift
interpreter.inputProvider = { prompt -> String? in
    // Must return user's input - but how to wait for UI?
}
```

We can't use async/await directly inside this callback because it's synchronous. We also can't block the main thread waiting for input or the UI would freeze.

## The Solution: Async/Await with Semaphore Bridge

The solution uses Swift's `CheckedContinuation` combined with a semaphore to bridge between:
- The **synchronous** interpreter running on a background thread
- The **async** SwiftUI interface on the main thread

### Data Flow Diagram

```
Background Thread (interpreter)     Main Thread (UI)
         |                               |
   inputProvider called                  |
         |                               |
   Task { @MainActor in                  |
      await inputCallback(prompt) ───────► show input field
   }                                     |
   semaphore.wait() ← BLOCKS             |
         |                     user types & submits
         |                               |
         | ◄──────────────── continuation.resume(input)
   semaphore.signal()                    |
         |                               |
   return result                    hide input field
         |                               |
   interpreter continues                 |
```

## Implementation

### JJEngine.swift

```swift
static func interpretAsync(
    _ program: Program,
    outputCallback: @escaping (String) -> Void,
    inputCallback: @escaping (String) async -> String?
) async -> String {
    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let interpreter = Interpreter()

            // Real-time output to UI
            interpreter.outputHandler = { text in
                DispatchQueue.main.async {
                    outputCallback(text)
                }
            }

            // Bridge sync callback to async UI
            interpreter.inputProvider = { prompt in
                let semaphore = DispatchSemaphore(value: 0)
                var result: String? = nil

                // Request input on main thread
                Task { @MainActor in
                    result = await inputCallback(prompt)
                    semaphore.signal()
                }

                // Block background thread until input arrives
                semaphore.wait()
                return result
            }

            // Run interpreter...
            try? interpreter.run(program)
            continuation.resume(returning: output)
        }
    }
}
```

### ContentView.swift

```swift
@State private var waitingForInput = false
@State private var inputPrompt = ""
@State private var inputContinuation: CheckedContinuation<String?, Never>?

// Running the interpreter
Task {
    let result = await JJEngine.interpretAsync(program,
        outputCallback: { output in
            self.runOutputs[tab] = output
        },
        inputCallback: { prompt in
            self.inputPrompt = prompt
            self.waitingForInput = true
            return await withCheckedContinuation { continuation in
                self.inputContinuation = continuation
            }
        }
    )
}

// When user submits input (in OutputView)
onInputSubmit: { input in
    inputContinuation?.resume(returning: input)
    inputContinuation = nil
    waitingForInput = false
}
```

## Key Points

1. **Background Thread**: The interpreter runs on `DispatchQueue.global()`, not the main thread. This allows it to safely block on the semaphore without freezing the UI.

2. **Semaphore Bridge**: The semaphore connects the sync world (interpreter) to the async world (UI). It only blocks the background thread.

3. **Task { @MainActor }**: Inside `inputProvider`, we spawn a task on the main actor to safely call the async `inputCallback` which updates UI state.

4. **CheckedContinuation**: The UI stores a continuation that gets resumed when the user submits input. This is Swift's safe way to bridge callback-based code to async/await.

5. **No Deadlock**: The main thread is never blocked. The semaphore only blocks the background interpreter thread while the main thread handles UI events.

## Compiled Targets

For compiled languages (C, Python, Go, etc.), stdin/stdout pipes are used instead:

```swift
let stdinPipe = Pipe()
process.standardInput = stdinPipe

// When input needed:
let inputData = (input + "\n").data(using: .utf8)!
stdinPipe.fileHandleForWriting.write(inputData)
```

The same async pattern is used to detect when the process is waiting for input (no output for a short time) and show the input field.
