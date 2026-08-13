// AXWebAreaStrategy.swift
// OpenClip
//
// Reads selected text and bounds for WebKit web areas from an
// AXElementInspector.Target snapshot.
import ApplicationServices
import Core

public struct AXWebAreaStrategy {
    /// kAXSelectedTextMarkerRange → AXStringForTextMarkerRange; bounds via
    /// kAXBoundsForTextMarkerRangeParameterizedAttribute.
    public static func read(from target: AXElementInspector.Target) -> TextResult? {
        // Marker-range path. The marker range must actually be an AXTextMarkerRange before
        // the live web area is asked to resolve it; under a fixture it is a plain object and
        // this strategy falls through to selectedText below.
        if let element = target.webArea ?? target.focusedElement,
           let markerRange = target.selectedTextMarkerRange,
           CFGetTypeID(markerRange) == AXTextMarkerRangeGetTypeID() {
            let range = markerRange as! AXTextMarkerRange
            if let text = string(for: element, markerRange: range), !text.isEmpty {
                return TextResult(text: text, bounds: bounds(for: element, markerRange: range))
            }
        }

        guard let text = target.selectedText, !text.isEmpty else { return nil }
        return TextResult(text: text, bounds: target.bounds)
    }

    /// Resolve a text marker range to its string via the
    /// kAXStringForTextMarkerRangeParameterizedAttribute parameterized attribute.
    private static func string(for element: AXUIElement, markerRange: AXTextMarkerRange) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForTextMarkerRangeParameterizedAttribute as CFString, markerRange, &value
        ) == .success else { return nil }
        return value as? String
    }

    /// The bounds for a text marker range via the
    /// kAXBoundsForTextMarkerRangeParameterizedAttribute parameterized attribute.
    private static func bounds(for element: AXUIElement, markerRange: AXTextMarkerRange) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForTextMarkerRangeParameterizedAttribute as CFString, markerRange, &value
        ) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }
}