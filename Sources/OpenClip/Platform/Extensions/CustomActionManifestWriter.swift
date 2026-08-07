// CustomActionManifestWriter.swift
// OpenClip
//
// App-target writer that turns a GUI-authored CustomAction into a single-action extension
// manifest package (`<identifier>/openclip.json`) inside the extensions directory, so Add/Edit
// sheets and the JSON manifest are one storage/list. The manifest identifier equals the action's
// id (e.g. `com.custom.<hex>`), and the action metadata carries an explicit `id` equal to that
// identifier so `ExtensionManager.uniformActionID` round-trips the loaded action's id verbatim.
import Foundation
import Core

public struct CustomActionManifestWriter: Sendable {
    /// Maps a `CustomAction` to the single-action `ExtensionMetadata` the manifest package stores.
    public static func metadata(for action: CustomAction) -> ExtensionMetadata {
        let actionMeta: ExtensionActionMetadata
        switch action.type {
        case .webSearch(let urlTemplate):
            actionMeta = ExtensionActionMetadata(
                id: action.id,
                title: action.title,
                icon: action.iconName,
                url: urlTemplate,
                type: "url"
            )
        case .textSnippet(let template):
            actionMeta = ExtensionActionMetadata(
                id: action.id,
                title: action.title,
                icon: action.iconName,
                type: "textsnippet",
                scriptCode: template
            )
        case .shellScript(let script, _):
            actionMeta = ExtensionActionMetadata(
                id: action.id,
                title: action.title,
                icon: action.iconName,
                type: "shell",
                scriptCode: script
            )
        }
        return ExtensionMetadata(
            identifier: action.id,
            name: action.title,
            actions: [actionMeta]
        )
    }

    /// Writes a single-action manifest package for `action` into `directoryURL/<id>/openclip.json`,
    /// replacing any existing package with the same identifier. Returns the manifest file URL.
    @discardableResult
    public static func write(
        action: CustomAction,
        to directoryURL: URL = Constants.extensionsDirectory
    ) throws -> URL {
        let packageDir = directoryURL.appendingPathComponent(action.id)
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        let manifestURL = packageDir.appendingPathComponent(Constants.manifestFileName)
        try ExtensionManifestStore.writeManifest(metadata(for: action), to: manifestURL)
        return manifestURL
    }
}
