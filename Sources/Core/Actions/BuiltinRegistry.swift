import Foundation

/// Core (AppKit-free) builtin actions. AppDelegate appends platform-specific ones.
public enum BuiltinRegistry {
    @MainActor
    public static func makeCoreBuiltins() -> [any Action] {
        [
            SearchAction(),
            DefineAction(),
            CopyAction(),
            CutAction(),
            PasteAction(),
            CalculateAction(),
        ]
    }
}
