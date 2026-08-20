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

public enum ExtensionSource: String, Sendable, Codable, Equatable {
    case store      // Installed from the in-app Store
    case package    // Installed via in-app file package picker (.zip, .openclipext)
    case developer  // Live local / developer workspace
    case local      // Legacy alias for developer / local

    public var isDeveloper: Bool {
        self == .developer || self == .local
    }
}

/// Events surfaced to the app target (via `ExtensionManager.onTrustChange`) so it can post
/// user notifications. Emitted by the trust gate, never by UI.
public enum ExtensionTrustChange: Sendable, Equatable {
    case newPackage(packageID: String, name: String)
    case tampered(packageID: String, name: String)
}