# AppleScript Action Runtime

The AppleScript action runtime ([`AppleScriptAction`](../../Sources/OpenClip/Actions/AppleScriptAction.swift)) allows OpenClip to automate macOS system applications (such as Safari, Finder, Mail, Notes, and Messages) using native `NSAppleScript`.

---

## Execution Architecture

```
Selection Context ---> AppleScriptAction.perform(_:) ---> NSAppleScript.executeAndReturnError()
 |
 v
 ActionResult (.copy / .success)
```

1. **Environment Setup**: The selected text string is sanitized by escaping double quotes (`"` $\rightarrow$ `\"`).
2. **Variable Injection**: OpenClip prepends variable declarations to the script string before execution:
 ```applescript
 set OPENCLIP_TEXT to "<escaped_selected_text>"
 set openclip_text to "<escaped_selected_text>"
 ```
3. **Background Thread Offloading**: Execution is dispatched onto a detached background task (`Task.detached`) to prevent blocking the main thread during AppleScript OS calls.

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

`AppleScriptAction` evaluates the `NSAppleScriptEventDescriptor` returned by `executeAndReturnError()`:

- **String Return Value**: If the script returns a non-empty string value (`output.stringValue`), `AppleScriptAction` returns `ActionResult.copy(str)` to copy the generated result to the pasteboard.
- **No Return Value (`nil` or empty string)**: If the script executes without returning text, it returns `ActionResult.success`.
- **Error Handling**: If `executeAndReturnError(&errorDict)` returns an error dictionary, the runtime throws `ActionResult.failure(error)` with the error message from `NSAppleScript.errorMessage`.
