import Foundation

/// Core (AppKit-free) builtin actions. AppDelegate appends platform-specific ones.
public enum BuiltinRegistry {
    @MainActor
    public static func makeCoreBuiltins() -> [any Action] {
        var actions: [any Action] = [
            SearchAction(),
            DefineAction(),
            CopyAction(),
            CutAction(),
            PasteAction(),
            CalculateAction(),
            TransformTextGroupAction()
        ]
        for transformCase in TransformCase.allCases {
            actions.append(TransformSubAction(transformCase: transformCase))
        }
        return actions
    }
}
