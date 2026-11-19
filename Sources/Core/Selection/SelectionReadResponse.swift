import Foundation

/// Domain outcome vocabulary: no platform APIs or user content in reason codes.
public enum SelectionReadStatus: String, Sendable, Codable, Equatable {
    case selection, noSelection, targetChanged, timedOut, copyBlocked, cancelled
    case clipboardFallback, policyBlocked, busy, failed, tooLarge
}

public struct TextReadResponse: Sendable {
    public let result: TextResult?
    public let isEditable: Bool
    /// True when the winning retrieval strategy was the keyboard-copy fallback, so Accessibility
    /// could not expose the selection and the app's Paste command is the only editability evidence.
    public let usedKeyboardCopy: Bool
    public let traceID: UInt64?
    public let status: SelectionReadStatus

    public init(
        result: TextResult? = nil,
        isEditable: Bool = false,
        usedKeyboardCopy: Bool = false,
        status: SelectionReadStatus,
        traceID: UInt64? = nil
    ) {
        self.result = result
        self.isEditable = isEditable
        self.usedKeyboardCopy = usedKeyboardCopy
        self.traceID = traceID
        self.status = status
    }
}

/// Clipboard fallback is a successful trigger with the original read outcome retained.
public struct SelectionTriggerResponse: Sendable {
    public let context: SelectionContext?
    public let canPaste: Bool?
    public let traceID: UInt64?
    public let status: SelectionReadStatus
    public let retrievalStatus: SelectionReadStatus?

    public init(context: SelectionContext? = nil, canPaste: Bool? = nil,
                status: SelectionReadStatus, retrievalStatus: SelectionReadStatus? = nil, traceID: UInt64? = nil) {
        self.context = context
        self.canPaste = canPaste
        self.traceID = traceID
        self.status = status
        self.retrievalStatus = retrievalStatus
    }
}
