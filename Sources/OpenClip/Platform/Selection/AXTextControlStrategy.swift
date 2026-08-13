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
              cfRange.location + cfRange.length <= fullValue.count else { return nil }

        let start = fullValue.index(fullValue.startIndex, offsetBy: cfRange.location)
        let end = fullValue.index(start, offsetBy: cfRange.length)
        return TextResult(text: String(fullValue[start..<end]), bounds: target.bounds)
    }
}