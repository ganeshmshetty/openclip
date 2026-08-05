// TextRetrieving.swift
// OpenClip
//
// Defines the protocol for extracting text and bounds from active applications using accessibility APIs or pasteboard fallbacks.
import Foundation
import CoreGraphics

public struct TextResult: Sendable {
    public let text: String
    public let bounds: CGRect?
    
    public init(text: String, bounds: CGRect? = nil) {
        self.text = text
        self.bounds = bounds
    }
}

public protocol TextRetrieving: Sendable {
    func retrieveText(for app: AppIdentity, policy: AppPolicyContext) async -> String?
    func retrieveTextResult(for app: AppIdentity, policy: AppPolicyContext) async -> TextResult?
}

public extension TextRetrieving {
    func retrieveText(for app: AppIdentity, policy: AppPolicyContext) async -> String? {
        await retrieveTextResult(for: app, policy: policy)?.text
    }
}
