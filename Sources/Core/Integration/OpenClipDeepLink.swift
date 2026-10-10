// OpenClipDeepLink.swift
// OpenClip
//
// The inbound `openclip://` URL grammar, parsed into a typed value. This is a small,
// fire-and-forget control surface: a URL asks OpenClip to do one thing and nothing is returned.
//
// The parser is pure and lives in Core so the grammar is testable without the app: the router that
// performs the side effects stays in the app target.
//
// Routes (host-based, matching the existing `openclip://install`):
//
//   openclip://install?id=<id>&url=<https-url>[&name=<name>]   install a store extension
//   openclip://command/<name>                                  run an app-level command
//
// There is deliberately no settings read/write route and no x-callback-url reply. A URL scheme is
// unauthenticated (any local process can open it) and a round-trip reply needs the caller to
// register a scheme and switch apps; both are the wrong tool for configuration or for reading a
// value back. Anything that needs a return value belongs in the CLI or App Intents.
import Foundation

/// An app-level verb the integration can invoke. These are side effects that are not a settings
/// write and carry no return value.
public enum IntegrationCommand: String, CaseIterable, Sendable, Equatable {
    /// Bring OpenClip's Settings window to the front.
    case openSettings = "open-settings"
    /// Temporarily pause the popup (the same pause the menu bar offers).
    case pause
    /// Clear a temporary pause.
    case resume
}

/// A parsed `openclip://` URL.
public enum OpenClipDeepLink: Equatable, Sendable {
    case install(id: String, name: String?, downloadURL: URL)
    case command(IntegrationCommand)

    public static let scheme = "openclip"

    /// Parses `url`, or returns `nil` when the scheme, host, or required parameters are missing.
    public static func parse(_ url: URL) -> OpenClipDeepLink? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []

        func value(_ name: String) -> String? {
            items.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        switch components.host?.lowercased() {
        case "install":
            guard let id = value("id"), !id.isEmpty,
                  let rawURL = value("url"), let downloadURL = URL(string: rawURL) else {
                return nil
            }
            return .install(id: id, name: value("name"), downloadURL: downloadURL)

        case "command":
            let raw = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let command = IntegrationCommand(rawValue: raw.lowercased()) else { return nil }
            return .command(command)

        default:
            return nil
        }
    }
}
