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
    func retrieveText(for app: any AppIdentifying, policy: AppPolicyContext) async -> String?
    func retrieveTextResult(for app: any AppIdentifying, policy: AppPolicyContext) async -> TextResult?
}

public extension TextRetrieving {
    func retrieveText(for app: any AppIdentifying, policy: AppPolicyContext) async -> String? {
        await retrieveTextResult(for: app, policy: policy)?.text
    }
}
