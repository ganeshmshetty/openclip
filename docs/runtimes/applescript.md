# AppleScript Extension Runtime

OpenClip supports native **AppleScript** execution via macOS `NSAppleScript` (`AppleScriptAction.swift`). AppleScript extensions allow you to seamlessly automate third-party Mac applications, control system settings, and interface with Apple Notes, Finder, Music, Mail, and System Events.

---

## Environment Variables & Scope

Before executing your AppleScript code, OpenClip populates the script scope with the active text selection under several variable names:

```applescript
set OPENCLIP_TEXT to "<highlighted_text>"
set openclip_text to "<highlighted_text>"
set POPCLIP_TEXT to "<highlighted_text>"
```

You can reference `OPENCLIP_TEXT` anywhere in your AppleScript.

---

## Copy-Pasteable AppleScript Examples

### Example 1: Add Selected Text to Apple Notes

Creates a new note inside Apple Notes containing your highlighted text.

```json
// openclip.json
{
  "Identifier": "com.openclip.addtoapplenotes",
  "Name": "Add to Apple Notes",
  "Actions": [
    {
      "Title": "New Note",
      "Icon": "symbol:note.text",
      "Script": "main.applescript"
    }
  ]
}
```

```applescript
-- main.applescript
tell application "Notes"
    activate
    tell account "iCloud"
        make new note at folder "Notes" with properties {name:"OpenClip Selection", body:OPENCLIP_TEXT}
    end tell
end tell
```

---

### Example 2: Apple Music Search & Play

Searches Apple Music for the selected song or artist and initiates playback.

```json
// openclip.json
{
  "Identifier": "com.openclip.applemusicsearch",
  "Name": "Search Apple Music",
  "Actions": [
    {
      "Title": "Play in Music",
      "Icon": "symbol:music.note",
      "Script": "main.applescript"
    }
  ]
}
```

```applescript
-- main.applescript
tell application "Music"
    activate
    search playlist "Library" for OPENCLIP_TEXT
    play track 1 of (search playlist "Library" for OPENCLIP_TEXT)
end tell
```

---

### Example 3: Send New Email with Selected Text (Apple Mail)

Drafts a new email message in Apple Mail with the selected text as the body.

```json
// openclip.json
{
  "Identifier": "com.openclip.mailselection",
  "Name": "Email Selection",
  "Actions": [
    {
      "Title": "Draft Email",
      "Icon": "symbol:envelope",
      "Script": "main.applescript"
    }
  ]
}
```

```applescript
-- main.applescript
tell application "Mail"
    activate
    set newMessage to make new outgoing message with properties {subject:"Selected Text Note", content:OPENCLIP_TEXT, visible:true}
end tell
```

---

### Example 4: Speak Selection (macOS Text-to-Speech)

Speaks the highlighted text using system text-to-speech.

```applescript
#openclip
# title: Speak Selection
# icon: speaker.wave.3
# applescript: say OPENCLIP_TEXT
```
