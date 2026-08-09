// UnavailableCanvasEngine.swift
// OpenClip
import Foundation
import Core

struct UnavailableCanvasEngine: CanvasScripting {
    func mount(_ request: CanvasMountRequest) async throws -> CanvasMountResult {
        throw NSError(domain: Constants.actionErrorDomain, code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Canvas runtime not available."])
    }
    func dispatch(_ request: CanvasDispatchRequest) async throws -> CanvasDispatchResult {
        throw NSError(domain: Constants.actionErrorDomain, code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Canvas runtime not available."])
    }
}
