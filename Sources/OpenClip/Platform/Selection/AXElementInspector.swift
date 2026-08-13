// AXElementInspector.swift
// OpenClip
//
// Fresh, one-shot resolution of the focused application and its focused UI element via the
// macOS accessibility API. Nothing is cached — every `inspect()` call resolves against the
// live accessibility tree.
import ApplicationServices
import CoreGraphics

public struct AXElementInspector {
    /// A snapshot of the focused application and UI element plus the AX attributes needed to
    /// gate and retrieve a text selection.
    ///
    /// `@unchecked Sendable` because it is an immutable snapshot of AX attribute values: the
    /// CF-type members are never mutated and are safe to hand from the blocking inspect worker to
    /// the consuming strategy.
    public struct Target: @unchecked Sendable {
        public let focusedApp: AXUIElement?
        public let focusedElement: AXUIElement?
        public let role: String?
        public let subRole: String?
        public let parentRoles: Set<String>
        public let containedInRoles: Set<String>
        public let webArea: AXUIElement?
        public let selectedText: String?
        public let selectedTextMarkerRange: AnyObject?
        public let value: String?
        public let selectedTextRange: AnyObject?
        public let bounds: CGRect?
    }

    /// Maximum number of ancestor levels walked when collecting parent/container roles and
    /// hunting for a containing web area.
    public static let ancestorWalkDepth = 4

    /// Canonical AX role string for WebKit web content. Not exposed as a named constant by this
    /// SDK, so it is spelled out here.
    private static let webAreaRole = "AXWebArea"

    /// Canonical AX attribute string for a web area's selected text marker range. Not exposed as
    /// a named constant by this SDK, so it is spelled out here.
    private static let selectedTextMarkerRangeAttribute = "AXSelectedTextMarkerRange"

    /// Resolve the focused application FIRST, then its focused UI element — fresh every call.
    ///
    /// Resolution order matters for reliability: the focused application is read from the
    /// system-wide element, and the focused UI element is then read from THAT application
    /// element. Reading `kAXFocusedUIElementAttribute` directly off the system-wide element
    /// is the classic source of stale or missing selection reads, so this inspector never does it.
    public static func inspect() -> Target {
        let systemWide = AXUIElementCreateSystemWide()

        // 1. Focused application — from the system-wide element.
        let focusedApp = read(systemWide, kAXFocusedApplicationAttribute).flatMap { axElement($0) }

        // 2. Focused UI element — from the focused application element, never system-wide.
        let focusedElement = focusedApp.flatMap { axElement(read($0, kAXFocusedUIElementAttribute)) }

        var role: String?
        var subRole: String?
        var parentRoles: Set<String> = []
        var containedInRoles: Set<String> = []
        var webArea: AXUIElement?

        if let focusedElement {
            role = read(focusedElement, kAXRoleAttribute) as? String
            subRole = read(focusedElement, kAXSubroleAttribute) as? String

            if role == webAreaRole {
                webArea = focusedElement
            }

            // Walk ancestors (bounded) for parent/container roles and web-area detection.
            var current = focusedElement
            for _ in 0..<ancestorWalkDepth {
                guard let parent = axElement(read(current, kAXParentAttribute)) else { break }
                if CFEqual(parent, current) { break }
                if let parentRole = read(parent, kAXRoleAttribute) as? String {
                    parentRoles.insert(parentRole)
                    containedInRoles.insert(parentRole)
                }
                if webArea == nil, read(parent, kAXRoleAttribute) as? String == webAreaRole {
                    webArea = parent
                }
                current = parent
            }
        }

        // Text/value attributes and selection bounds, where supported.
        let selectedText = focusedElement.flatMap { read($0, kAXSelectedTextAttribute) as? String }
        let selectedTextMarkerRange = selectedTextMarkerRange(focusedElement: focusedElement, webArea: webArea)
        let value = focusedElement.flatMap { read($0, kAXValueAttribute) as? String }
        let selectedTextRange = focusedElement.flatMap { read($0, kAXSelectedTextRangeAttribute) }
        let bounds = bounds(for: focusedElement, range: selectedTextRange)

        return Target(
            focusedApp: focusedApp,
            focusedElement: focusedElement,
            role: role,
            subRole: subRole,
            parentRoles: parentRoles,
            containedInRoles: containedInRoles,
            webArea: webArea,
            selectedText: selectedText,
            selectedTextMarkerRange: selectedTextMarkerRange,
            value: value,
            selectedTextRange: selectedTextRange,
            bounds: bounds
        )
    }

    /// Reads `AXSelectedTextMarkerRange` attribute from `focusedElement`, falling back to `webArea` if `focusedElement` is nil or yields no marker range.
    static func selectedTextMarkerRange(
        focusedElement: AXUIElement?,
        webArea: AXUIElement?,
        read: (AXUIElement, String) -> CFTypeRef? = { read($0, $1) }
    ) -> AnyObject? {
        focusedElement.flatMap { read($0, selectedTextMarkerRangeAttribute) } ?? webArea.flatMap { read($0, selectedTextMarkerRangeAttribute) }
    }

    /// Reads a single AX attribute, returning `nil` on any error or unsupported attribute.
    private static func read(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    /// Returns the value as an `AXUIElement` only when it actually is one. `as? AXUIElement`
    /// from a CF value is diagnosed as an unconditional cast, so the CF type ID is checked first.
    private static func axElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return value as! AXUIElement
    }

    /// The selection bounds for a text range via `kAXBoundsForRangeParameterizedAttribute`,
    /// or `nil` when the element or range does not support it.
    private static func bounds(for element: AXUIElement?, range: CFTypeRef?) -> CGRect? {
        guard let element, let range else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &boundsRef
        ) == .success,
            let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }
}