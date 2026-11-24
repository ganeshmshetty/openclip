import AppKit

/// Read consent for `NSPasteboard.general`. The system reports it as an access behavior on
/// macOS 15.4+; older systems have no per-process setting, so reads keep their old behavior.
internal struct PasteboardAccessPolicy: Sendable {
    internal enum Status: Equatable, Sendable {
        case unknown
        case allowed
        case asks
        case denied
    }

    internal typealias Reader = @Sendable () -> Status

    private let read: Reader

    internal init(read: @escaping Reader = PasteboardAccessPolicy.systemStatus) {
        self.read = read
    }

    internal var status: Status { read() }

    /// Only an explicit always-deny blocks the read. Ask/default/unknown keep the existing path.
    internal var deniesReads: Bool { status == .denied }

    private static func systemStatus() -> Status {
        guard #available(macOS 15.4, *) else { return .unknown }
        switch NSPasteboard.general.accessBehavior {
        case .alwaysDeny: return .denied
        case .alwaysAllow: return .allowed
        case .ask: return .asks
        default: return .unknown
        }
    }
}
