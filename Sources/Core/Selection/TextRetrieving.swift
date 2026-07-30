public protocol TextRetrieving: Sendable {
    func retrieveText(for app: any AppIdentifying) async -> String?
}
