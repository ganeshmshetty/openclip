import Foundation
import SwiftUI

@MainActor
public final class DynamicSFSymbolProvider: ObservableObject, Sendable {
    public static let shared = DynamicSFSymbolProvider()

    @Published public private(set) var allSymbols: [String] = []
    @Published public private(set) var isLoaded = false

    private init() {
        Task {
            await loadSystemSymbols()
        }
    }

    private func loadSystemSymbols() async {
        let symbols = await Task.detached(priority: .userInitiated) { () -> [String] in
            let plistURL = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
            guard let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let symbolsDict = plist["symbols"] as? [String: Any] else {
                // Fallback default list if system plist cannot be read
                return [
                    "doc.on.clipboard", "scissors", "doc.text", "magnifyingglass", "wand.and.stars",
                    "link", "globe", "envelope", "square.and.pencil", "arrow.up.circle",
                    "checkmark.circle", "xmark.circle", "star", "heart", "bookmark", "tag", "paperplane",
                    "trash", "folder", "play.circle", "pause.circle", "music.note", "terminal", "gearshape"
                ]
            }

            let rawNames = Array(symbolsDict.keys)
            // Filter out localized variant suffixes (e.g. .ar, .hi, .zh, .ja, .ko, .ru, .he)
            let localeSuffixes = [".ar", ".hi", ".zh", ".ja", ".ko", ".ru", ".he", ".th", ".el", ".fa"]
            let cleanSymbols = rawNames.filter { name in
                !localeSuffixes.contains(where: { name.hasSuffix($0) })
            }.sorted()

            return cleanSymbols
        }.value

        self.allSymbols = symbols
        self.isLoaded = true
    }

    public func search(query: String, limit: Int = 100) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return Array(allSymbols.prefix(limit))
        }
        
        let terms = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        let matches = allSymbols.filter { sym in
            let lower = sym.lowercased()
            return terms.allSatisfy { lower.contains($0) }
        }
        
        return Array(matches.prefix(limit))
    }
}
