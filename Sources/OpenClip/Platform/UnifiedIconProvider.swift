import Foundation
import SwiftUI

public struct IconEntry: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let library: String // "SF Symbol", "Font Awesome", "Lucide", "Material"
    
    public init(id: String, name: String, library: String) {
        self.id = id
        self.name = name
        self.library = library
    }
}

@MainActor
public final class UnifiedIconProvider: ObservableObject, Sendable {
    public static let shared = UnifiedIconProvider()

    @Published public private(set) var allIcons: [IconEntry] = []
    @Published public private(set) var isLoaded = false

    private init() {
        Task {
            await loadAllIcons()
        }
    }

    private func loadAllIcons() async {
        let entries = await Task.detached(priority: .userInitiated) { () -> [IconEntry] in
            var results: [IconEntry] = []

            // 1. Scan 9,000+ native macOS SF Symbols dynamically
            let plistURL = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
            if let data = try? Data(contentsOf: plistURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let symbolsDict = plist["symbols"] as? [String: Any] {
                let localeSuffixes = [".ar", ".hi", ".zh", ".ja", ".ko", ".ru", ".he", ".th", ".el", ".fa"]
                let sfList = symbolsDict.keys.filter { name in
                    !localeSuffixes.contains(where: { name.hasSuffix($0) })
                }.sorted()
                for sym in sfList {
                    results.append(IconEntry(id: sym, name: sym, library: "SF Symbol"))
                }
            } else {
                let defaultSF = ["doc.on.clipboard", "scissors", "doc.text", "magnifyingglass", "wand.and.stars", "globe", "play.circle", "gearshape"]
                for sym in defaultSF {
                    results.append(IconEntry(id: sym, name: sym, library: "SF Symbol"))
                }
            }

            // 2. Font Awesome Brand & Action Icons
            let faList = [
                "fa:youtube", "fa:github", "fa:spotify", "fa:apple", "fa:google", "fa:twitter",
                "fa:discord", "fa:slack", "fa:figma", "fa:gitlab", "fa:linkedin", "fa:instagram",
                "fa:reddit", "fa:twitch", "fa:codepen", "fa:medium", "fa:trello", "fa:jira",
                "fa:code", "fa:terminal", "fa:database", "fa:server", "fa:bug", "fa:cube",
                "fa:folder", "fa:file", "fa:copy", "fa:paste", "fa:cut", "fa:trash", "fa:star",
                "fa:heart", "fa:bookmark", "fa:tag", "fa:envelope", "fa:search", "fa:filter"
            ]
            for fa in faList {
                results.append(IconEntry(id: fa, name: fa, library: "Font Awesome"))
            }

            // 3. Lucide Icons
            let lucideList = [
                "lucide:zap", "lucide:search", "lucide:copy", "lucide:cut", "lucide:paste",
                "lucide:terminal", "lucide:globe", "lucide:cpu", "lucide:code", "lucide:layers",
                "lucide:sparkles", "lucide:shield", "lucide:external-link", "lucide:download",
                "lucide:check", "lucide:x", "lucide:arrow-right", "lucide:corner-down-left",
                "lucide:play", "lucide:pause", "lucide:music", "lucide:folder", "lucide:file"
            ]
            for luc in lucideList {
                results.append(IconEntry(id: luc, name: luc, library: "Lucide"))
            }

            // 4. Google Material Symbols
            let matList = [
                "material:search", "material:settings", "material:favorite", "material:star",
                "material:home", "material:build", "material:code", "material:terminal",
                "material:content_copy", "material:content_cut", "material:content_paste",
                "material:delete", "material:edit", "material:folder", "material:visibility",
                "material:lock", "material:security", "material:extension", "material:play_arrow"
            ]
            for mat in matList {
                results.append(IconEntry(id: mat, name: mat, library: "Material"))
            }

            return results
        }.value

        self.allIcons = entries
        self.isLoaded = true
    }

    /// Unified search across ALL libraries simultaneously in one place
    public func search(query: String, limit: Int = 160) -> [IconEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return Array(allIcons.prefix(limit))
        }

        let terms = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        let matches = allIcons.filter { item in
            let lower = item.id.lowercased()
            return terms.allSatisfy { lower.contains($0) }
        }

        return Array(matches.prefix(limit))
    }
}
