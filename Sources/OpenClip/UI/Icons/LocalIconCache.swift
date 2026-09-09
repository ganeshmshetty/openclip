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
    private final class Entry {
        let image: NSImage?
        init(_ image: NSImage?) { self.image = image }
    }

    static let shared = LocalIconCache()

    private let cache = NSCache<NSString, Entry>()

    private init() {
        // Icons render at ~14-16pt; cap the count so a large catalog of custom icons can't grow
        // the cache unbounded. `countLimit` is a soft cap — NSCache evicts under memory pressure.
        cache.countLimit = 128
    }

    /// Returns the decoded image for `url`, reading and decoding the file at most once.
    /// SVGs are marked as templates so they tint to the theme's foreground.
    /// Raster images and favicons retain their original colors.
    func image(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached.image
        }
        guard let image = NSImage(contentsOf: url) else {
            cache.setObject(Entry(nil), forKey: key)
            return nil
        }
        let isSVG = url.pathExtension.lowercased() == "svg"
        image.isTemplate = isSVG
        cache.setObject(Entry(image), forKey: key)
        return image
    }

    /// Evicts the cached image for `url` so subsequent reads re-read the file from disk.
    func invalidate(for url: URL) {
        let key = url.path as NSString
        cache.removeObject(forKey: key)
    }

    /// Clears the entire cache.
    func clear() {
        cache.removeAllObjects()
    }
}
