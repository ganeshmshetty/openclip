// AppIdentifying.swift
// OpenClip
//
// Defines the protocol for identifying external application bundle identifiers and localized names.
public protocol AppIdentifying: Sendable {
    var bundleIdentifier: String? { get }
    var localizedName: String? { get }
}
