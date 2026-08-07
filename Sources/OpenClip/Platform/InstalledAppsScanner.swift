// InstalledAppsScanner.swift
// OpenClip
//
// Scans installed macOS applications in system directories to populate application selection interfaces.
import AppKit
import Foundation
import Core

public struct InstalledAppInfo: Identifiable, Sendable, Hashable {
    public var id: String { bundleIdentifier }
    public let name: String
    public let bundleIdentifier: String
    public let path: String
    
    public init(name: String, bundleIdentifier: String, path: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }
}

@MainActor
public final class InstalledAppsScanner: ObservableObject {
    @Published public var installedApps: [InstalledAppInfo] = []
    @Published public var isLoading: Bool = false
    
    public init() {}
    
    public func scanInstalledApps() async -> [InstalledAppInfo] {
        self.isLoading = true
        defer { self.isLoading = false }
        
        let searchDirectories = [
            "/Applications",
            "/System/Applications",
            ("/Applications/Utilities" as NSString).expandingTildeInPath,
            ("~/Applications" as NSString).expandingTildeInPath
        ]
        
        var results: [InstalledAppInfo] = []
        var seenBundleIDs = Set<String>()
        let fm = FileManager.default
        
        for dir in searchDirectories {
            let dirURL = URL(fileURLWithPath: dir)
            guard let contents = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else {
                Log.settings.debug("Could not read installed-apps directory \(dir)")
                continue
            }
            
            for fileURL in contents {
                if fileURL.pathExtension == "app" {
                    if let bundle = Bundle(url: fileURL),
                       let bundleID = bundle.bundleIdentifier,
                       !seenBundleIDs.contains(bundleID) {
                        
                        seenBundleIDs.insert(bundleID)
                        let appName = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                            ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                            ?? fileURL.deletingPathExtension().lastPathComponent
                        
                        results.append(InstalledAppInfo(
                            name: appName,
                            bundleIdentifier: bundleID,
                            path: fileURL.path
                        ))
                    }
                }
            }
        }
        
        let sorted = results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.installedApps = sorted
        return sorted
    }
}
