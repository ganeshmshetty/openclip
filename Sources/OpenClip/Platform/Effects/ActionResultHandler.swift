import Foundation
import AppKit
import Core

public protocol ActionResultHandler: Sendable {
    @MainActor
    func handle(_ result: ActionResult) async throws
}

@MainActor
public final class DefaultActionResultHandler: ActionResultHandler, Sendable {
    public init() {}

    public func handle(_ result: ActionResult) async throws {
        switch result {
        case .copy(let text), .cut(let text):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        case .paste(let text):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .showServices(let text):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        case .simulatePaste:
            break
        case .success, .none:
            break
        case .failure(let error):
            throw error
        }
    }
}
