public protocol AppIdentifying: Sendable {
    var bundleIdentifier: String? { get }
    var localizedName: String? { get }
}
