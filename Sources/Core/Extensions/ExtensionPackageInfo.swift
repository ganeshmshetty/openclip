// ExtensionPackageInfo.swift
// OpenClip
//
// Pure Core presentation model and resolver for installed extension packages.
// Extracts unique packages from loaded actions, determines whole-package enable state,
// and sorts for user-facing menus and lists.
import Foundation

/// Pure presentation summary of an installed extension package.
public struct ExtensionPackageInfo: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let isEnabled: Bool

    public init(id: String, displayName: String, isEnabled: Bool) {
        self.id = id
        self.displayName = displayName
        self.isEnabled = isEnabled
    }
}

/// Resolves installed extension packages from an action list.
public enum ExtensionPackageResolver {
    /// Extracts unique extension packages from `actions`, checks their enabled state against
    /// `disabledPackages`, and returns them sorted alphabetically by display name.
    public static func resolvePackages(
        from actions: [any Action],
        disabledPackages: Set<String>
    ) -> [ExtensionPackageInfo] {
        var seen = Set<String>()
        var result: [ExtensionPackageInfo] = []

        for action in actions {
            guard let packageID = ActionIdentity.extensionPackageID(of: action),
                  !seen.contains(packageID) else { continue }
            seen.insert(packageID)

            let displayName: String
            if case .extensionPkg(let badgeName) = action.chrome.badge, !badgeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                displayName = badgeName
            } else {
                displayName = packageID
            }

            let isEnabled = !disabledPackages.contains(packageID)
            result.append(ExtensionPackageInfo(id: packageID, displayName: displayName, isEnabled: isEnabled))
        }

        return result.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}
