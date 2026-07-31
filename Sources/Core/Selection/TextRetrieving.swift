public protocol TextRetrieving: Sendable {
    func retrieveText(for app: any AppIdentifying, policy: AppPolicyContext) async -> String?
}
