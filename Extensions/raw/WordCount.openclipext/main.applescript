global OPENCLIP_TEXT, openclip_text
set rawText to OPENCLIP_TEXT

set charCount to length of rawText
set wordCount to count of words of rawText
set lineCount to count of paragraphs of rawText

set msg to (wordCount as text) & " words  •  " & (charCount as text) & " chars  •  " & (lineCount as text) & " lines"
display notification msg with title "Word & Character Count"
