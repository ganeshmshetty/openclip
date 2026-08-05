// AppIdentifying.swift
// OpenClip
//
// Represents external application identity (bundle identifier and localized name).

public struct AppIdentity: Sendable, Equatable, Hashable {
    public let bundleIdentifier: String?
    public let localizedName: String?

    public init(bundleIdentifier: String? = nil, localizedName: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}

