// AXTextControlStrategy.swift
// OpenClip
//
// Reads selected text and bounds for native text controls from an
// AXElementInspector.Target snapshot.
import ApplicationServices
import Core

public struct AXTextControlStrategy {
    /// kAXSelectedTextAttribute, falling back to value + selectedTextRange substring.
    public static func read(from target: AXElementInspector.Target) -> TextResult? {
        if let text = target.selectedText, !text.isEmpty {
            return TextResult(text: text, bounds: target.bounds)
        }

        guard let fullValue = target.value, !fullValue.isEmpty,
              let rangeValue = target.selectedTextRange,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }

        var cfRange = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange),
              cfRange.length > 0,
              cfRange.location >= 0,
              cfRange.location + cfRange.length <= fullValue.utf16.count else { return nil }

        // AXValueGetValue reports UTF-16 code-unit offsets, so index via the UTF-16 view rather
        // than Character-based offsets (which would mis-slice multi-byte strings).
        let start = String.Index(utf16Offset: cfRange.location, in: fullValue)
        let end = String.Index(utf16Offset: cfRange.location + cfRange.length, in: fullValue)
        return TextResult(text: String(fullValue[start..<end]), bounds: target.bounds)
    }
}