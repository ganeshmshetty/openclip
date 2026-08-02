import Foundation
import SwiftUI

public enum IconLibraryType: String, CaseIterable, Identifiable {
    case sfSymbols = "SF Symbols"
    case fontAwesome = "Font Awesome & Brands"
    case lucide = "Lucide Icons"
    case material = "Material Symbols"
    
    public var id: String { rawValue }
}

@MainActor
public final class DynamicSFSymbolProvider: ObservableObject, Sendable {
    public static let shared = DynamicSFSymbolProvider()

    @Published public private(set) var sfSymbols: [String] = []
    @Published public private(set) var fontAwesomeIcons: [String] = []
    @Published public private(set) var lucideIcons: [String] = []
    @Published public private(set) var materialIcons: [String] = []
    @Published public private(set) var isLoaded = false

    private init() {
        Task {
            await loadAllIconLibraries()
        }
    }

    private func loadAllIconLibraries() async {
        let (sf, fa, lucide, mat) = await Task.detached(priority: .userInitiated) { () -> ([String], [String], [String], [String]) in
            // 1. Scan 9,000+ native macOS SF Symbols
            var sfList: [String] = []
            let plistURL = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
            if let data = try? Data(contentsOf: plistURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let symbolsDict = plist["symbols"] as? [String: Any] {
                let localeSuffixes = [".ar", ".hi", ".zh", ".ja", ".ko", ".ru", ".he", ".th", ".el", ".fa"]
                sfList = symbolsDict.keys.filter { name in
                    !localeSuffixes.contains(where: { name.hasSuffix($0) })
                }.sorted()
            } else {
                sfList = ["doc.on.clipboard", "scissors", "doc.text", "magnifyingglass", "wand.and.stars", "globe", "play.circle", "gearshape"]
            }

            // 2. Font Awesome Brand & Solid Icons
            let faList = [
                "fa:youtube", "fa:github", "fa:spotify", "fa:apple", "fa:google", "fa:twitter",
                "fa:discord", "fa:slack", "fa:figma", "fa:gitlab", "fa:linkedin", "fa:instagram",
                "fa:reddit", "fa:twitch", "fa:codepen", "fa:medium", "fa:trello", "fa:jira",
                "fa:code", "fa:terminal", "fa:database", "fa:server", "fa:bug", "fa:cube",
                "fa:folder", "fa:file", "fa:copy", "fa:paste", "fa:cut", "fa:trash", "fa:star",
                "fa:heart", "fa:bookmark", "fa:tag", "fa:envelope", "fa:search", "fa:filter"
            ]

            // 3. Lucide Icons
            let lucideList = [
                "lucide:zap", "lucide:search", "lucide:copy", "lucide:cut", "lucide:paste",
                "lucide:terminal", "lucide:globe", "lucide:cpu", "lucide:code", "lucide:layers",
                "lucide:sparkles", "lucide:shield", "lucide:external-link", "lucide:download",
                "lucide:check", "lucide:x", "lucide:arrow-right", "lucide:corner-down-left",
                "lucide:play", "lucide:pause", "lucide:music", "lucide:folder", "lucide:file"
            ]

            // 4. Google Material Symbols
            let matList = [
                "material:search", "material:settings", "material:favorite", "material:star",
                "material:home", "material:build", "material:code", "material:terminal",
                "material:content_copy", "material:content_cut", "material:content_paste",
                "material:delete", "material:edit", "material:folder", "material:visibility",
                "material:lock", "material:security", "material:extension", "material:play_arrow"
            ]

            return (sfList, faList, lucideList, matList)
        }.value

        self.sfSymbols = sf
        self.fontAwesomeIcons = fa
        self.lucideIcons = lucide
        self.materialIcons = mat
        self.isLoaded = true
    }

    public func search(library: IconLibraryType, query: String, limit: Int = 120) -> [String] {
        let pool: [String]
        switch library {
        case .sfSymbols: pool = sfSymbols
        case .fontAwesome: pool = fontAwesomeIcons
        case .lucide: pool = lucideIcons
        case .material: pool = materialIcons
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return Array(pool.prefix(limit))
        }

        let terms = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        let matches = pool.filter { sym in
            let lower = sym.lowercased()
            return terms.allSatisfy { lower.contains($0) }
        }

        return Array(matches.prefix(limit))
    }
}
