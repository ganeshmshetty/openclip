on run
    tell application "Music"
        activate
    end tell
    open location "music://music.apple.com/search?term=" & OPENCLIP_TEXT
end run
