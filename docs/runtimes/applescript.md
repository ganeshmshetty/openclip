# AppleScript Action Runtime

The AppleScript action runtime ([`AppleScriptAction`](../../Sources/OpenClip/Platform/Runtimes/AppleScriptAction.swift)) allows OpenClip to automate macOS system applications (such as Safari, Finder, Mail, Notes, and Messages).

---

## Execution Architecture

```
Selection Context ---> AppleScriptAction.perform(_:)
                         |
                         v
              AppleScriptRunner (osascript subprocess)
                         |   ShellProcessRunner.run (30s watchdog)
                         v
  ActionResult (.copy / .success / .failure)
```

1. **Environment Setup**: The selected text string is sanitized by escaping double quotes (`"` $\rightarrow$ `\"`).
2. **Variable Injection**: OpenClip prepends variable declarations to the script string before execution:
  ```applescript
  set OPENCLIP_TEXT to "<escaped_selected_text>"
  set openclip_text to "<escaped_selected_text>"
  ```
3. **Subprocess Execution**: The script runs as an `/usr/bin/osascript` subprocess through
   [`AppleScriptRunner`](../../Sources/OpenClip/Platform/AppleScriptRunner.swift), which delegates
   to the shared `ShellProcessRunner` (the same 30 s watchdog used by shell actions).

### Why a subprocess (bounded off-main strategy)

In-process `NSAppleScript.executeAndReturnError()` blocks the calling thread until the target
application answers over Apple Events — it cannot be cancelled, has no timeout, and a hung
`tell application` permanently parks a cooperative-pool thread. `NSAppleScript` is also not
thread-safe across instances. Running each script as a killable subprocess keeps the
cooperative-thread pool free: the watchdog terminates the subprocess at `Constants.scriptTimeout`,
so a stuck script can never wedge a thread forever. Callers that need a tighter budget pass an
explicit `timeout` that shortens the subprocess watchdog (e.g. `BrowserScriptStrategy` bounds each
AppleScript run at `Constants.browserScriptTimeout`, 1.0 s) instead of racing a separate deadline.

`BrowserScriptStrategy` (via `AppleScriptRunner`) and `AppleScriptAction` both route through the
shared subprocess runner. The deadline-capped AX inspect in `SelectionRetrievalCoordinator` uses
`OnceResume` to guarantee exactly-once continuation resume between the worker and the deadline.

---

## Example AppleScript Snippets

### Example 1: Create New Note in macOS Notes App

```applescript
tell application "Notes"
 activate
 make new note at folder "Notes" with data OPENCLIP_TEXT
end tell
```

### Example 2: Transform Selected Text to Uppercase

```applescript
use framework "Foundation"
use scripting additions

set currentText to NSString's stringWithString:OPENCLIP_TEXT
set upperText to currentText's uppercaseString()
return (upperText as text)
```

---

## Return Values & Side Effects

`AppleScriptAction` reads the script's stdout (the value osascript prints for the last statement):

- **String Return Value**: If the script returns a non-empty string value, `AppleScriptAction` returns `ActionResult.copy(str)` to copy the generated result to the pasteboard.
- **No Return Value (empty)**: If the script executes without returning text, it returns `ActionResult.success`.
- **Error Handling**: On a non-zero subprocess exit (the AppleScript error text goes to stderr), the runtime returns `ActionResult.failure(error)` with the error message.
- **Timeout**: If the subprocess is still running after `Constants.scriptTimeout`, the watchdog terminates it and execution surfaces as a timeout failure.
