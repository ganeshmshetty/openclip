// ContentFingerprint.swift
// OpenClip
//
// Single home for content SHA-256 fingerprinting. `ManifestValidator` uses it for the manifest
// fingerprint and the trust gate uses it for package/script hashing, so both digests are the
// same algorithm. Pure Core — no AppKit/SwiftUI.
import Foundation
import CryptoKit

public enum ContentFingerprint {
    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}