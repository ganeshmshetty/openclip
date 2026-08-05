// AppIdentifying+NSRunningApplication.swift
// OpenClip
//
// Extends AppIdentity to initialize from NSRunningApplication.
import AppKit
import Core

extension AppIdentity {
    public init(_ app: NSRunningApplication) {
        self.init(bundleIdentifier: app.bundleIdentifier, localizedName: app.localizedName)
    }
}

