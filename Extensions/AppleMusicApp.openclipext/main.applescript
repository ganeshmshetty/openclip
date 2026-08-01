tell application "Music"
    activate
    set searchText to OPENCLIP_TEXT
    open location ("music://music.apple.com/search?term=" & searchText)
end tell
