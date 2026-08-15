// ExtensionTrustState.swift
// OpenClip
//
// Trust-state primitives for the extension consent gate. Trust is a per-package decision
// keyed by manifest identifier, persisted as raw strings under SettingKey.extensionTrust.
// Pure Core — no AppKit/SwiftUI.
import Foundation

public enum ExtensionTrustState: String, Sendable, Codable, Equatable {
    case seen      // detected and its notification already fired; never enabled
    case trusted   // user enabled it; content hash recorded at enable time
    case revoked   // user explicitly disabled it
}

/// Events surfaced to the app target (via `ExtensionManager.onTrustChange`) so it can post
/// user notifications. Emitted by the trust gate, never by UI.
public enum ExtensionTrustChange: Sendable, Equatable {
    case newPackage(packageID: String, name: String)
    case tampered(packageID: String, name: String)
}