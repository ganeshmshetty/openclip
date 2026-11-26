// PermissionCopy.swift
// OpenClip
//
// macOS 27 renamed the Accessibility privacy pane to Device Control and Data Access.
// The AX permission and its Settings deep link are unchanged, so only the user-facing
// name follows the OS.
import SwiftUI

enum PermissionCopy {
    static var paneName: LocalizedStringKey {
        if #available(macOS 27.0, *) {
            return "Device Control and Data Access"
        }
        return "Accessibility"
    }

    static var accessTitle: LocalizedStringKey {
        if #available(macOS 27.0, *) {
            return "Device Control and Data Access"
        }
        return "Accessibility Access"
    }

    /// English catalog key for the settings search index, which stores plain strings.
    static var accessTitleKey: String {
        if #available(macOS 27.0, *) {
            return "Device Control and Data Access"
        }
        return "Accessibility Access"
    }

    static var requiredTitle: LocalizedStringKey {
        if #available(macOS 27.0, *) {
            return "Device Control and Data Access Required"
        }
        return "Accessibility Access Required"
    }

    static var grantedTitle: LocalizedStringKey {
        if #available(macOS 27.0, *) {
            return "Device Control and Data Access Granted"
        }
        return "Accessibility Permission Granted"
    }

    static var grantPrompt: LocalizedStringKey {
        if #available(macOS 27.0, *) {
            return "Grant Device Control and Data Access to detect your text selections."
        }
        return "Grant Accessibility to detect your text selections."
    }

    static var needsAccessDescription: LocalizedStringKey {
        if #available(macOS 27.0, *) {
            return "OpenClip needs Device Control and Data Access to detect selected text and display action bars."
        }
        return "OpenClip needs Accessibility access to detect selected text and display action bars."
    }

    static var reEnableDescription: LocalizedStringKey {
        if #available(macOS 27.0, *) {
            return "macOS requires re-enabling Device Control and Data Access to continue detecting text selections."
        }
        return "macOS requires re-enabling Accessibility to continue detecting text selections."
    }
}
