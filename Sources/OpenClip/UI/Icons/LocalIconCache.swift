// LocalIconCache.swift
// OpenClip
//
// Cache for local-file action icons. `NSImage(contentsOf:)` reads and decodes the file on the
// calling thread; with the popup body re-evaluating on every mouse move, that synchronous disk
// I/O was re-running on the main actor per render. `LocalIconCache` keeps one decoded image per
// file URL so each file is read and decoded at most once. Backed by `NSCache`, which is
// thread-safe by design; bound to the main actor only because that is where every call site lives.
import Foundation
import AppKit

@MainActor
final class LocalIconCache {
    static let shared = LocalIconCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        // Icons render at ~14-16pt; cap the count so a large catalog of custom icons can't grow
        // the cache unbounded. `countLimit` is a soft cap — NSCache evicts under memory pressure.
        cache.countLimit = 128
    }

    /// Returns the decoded image for `url`, reading and decoding the file at most once.
    func image(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
