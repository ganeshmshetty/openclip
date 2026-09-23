// SettingsDesignTokens.swift
// OpenClip
//
// Central design tokens for OpenClip's Settings window.
// Holds semantic colors, materials, radii, spacing, pitch, and icon tile color definitions
// to match the near-black window and inset detail card style.

import SwiftUI
import AppKit
import Core

public enum SettingsDesignTokens {

    // MARK: - Colors

    /// Scrim overlay atop the behind-window Liquid Glass blur.
    public static var windowScrim: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 0.0, alpha: 0.32)
            } else {
                return NSColor(white: 1.0, alpha: 0.36)
            }
        }))
    }

    /// Very dark near-black background for the window (solid fallback or underlay).
    public static var windowBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.051, green: 0.051, blue: 0.059, alpha: 1.0) // #0D0D0F
            } else {
                return NSColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1.0)
            }
        }))
    }

    /// Primary text color (adapts to dark and light modes).
    public static var primaryText: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor.white
            } else {
                return NSColor.labelColor
            }
        }))
    }

    /// Secondary text color (adapts to dark and light modes).
    public static var secondaryText: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.65)
            } else {
                return NSColor.secondaryLabelColor
            }
        }))
    }

    /// Tertiary text / placeholder color.
    public static var tertiaryText: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.38)
            } else {
                return NSColor.tertiaryLabelColor
            }
        }))
    }

    /// Lighter, softer blue tone for glass action buttons (e.g. Generate, Check for Updates).
    public static var glassButtonBlue: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(srgbRed: 0.44, green: 0.74, blue: 1.0, alpha: 1.0)
            } else {
                return NSColor(srgbRed: 0.12, green: 0.52, blue: 0.94, alpha: 1.0)
            }
        }))
    }

    /// Lighter, softer red/rose tone for destructive glass buttons (e.g. Delete).
    public static var glassButtonRed: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(srgbRed: 1.0, green: 0.48, blue: 0.52, alpha: 1.0)
            } else {
                return NSColor(srgbRed: 0.90, green: 0.28, blue: 0.32, alpha: 1.0)
            }
        }))
    }

    /// The fill for the inset detail card (translucent smoked glass matching the sidebar with balanced contrast).
    public static var detailCardBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.086, green: 0.086, blue: 0.098, alpha: 0.52)
            } else {
                return NSColor(white: 1.0, alpha: 0.60)
            }
        }))
    }

    /// Subtle border for the detail card.
    public static var detailCardBorder: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.08)
            } else {
                return NSColor(white: 0.0, alpha: 0.10)
            }
        }))
    }

    /// The fill for individual section cards inside the detail pane (elevated glass with high contrast).
    public static var sectionCardBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.125, green: 0.125, blue: 0.141, alpha: 0.68)
            } else {
                return NSColor(white: 0.97, alpha: 0.72)
            }
        }))
    }

    /// Border for section cards inside the detail pane.
    public static var sectionCardBorder: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.06)
            } else {
                return NSColor(white: 0.0, alpha: 0.08)
            }
        }))
    }

    /// Background for the sidebar search field.
    public static var sidebarSearchBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.08)
            } else {
                return NSColor(white: 0.0, alpha: 0.06)
            }
        }))
    }

    /// Border for the sidebar search capsule.
    public static var sidebarSearchBorder: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.06)
            } else {
                return NSColor(white: 0.0, alpha: 0.08)
            }
        }))
    }

    /// Placeholder and icon color for the sidebar search field.
    public static var sidebarSearchPlaceholder: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.45)
            } else {
                return NSColor(white: 0.0, alpha: 0.45)
            }
        }))
    }

    /// Selected sidebar row highlight (subtle translucent highlight, NOT accent color).
    public static var selectedRowBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.11)
            } else {
                return NSColor(white: 0.0, alpha: 0.08)
            }
        }))
    }

    /// Hovered sidebar row highlight.
    public static var hoveredRowBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.05)
            } else {
                return NSColor(white: 0.0, alpha: 0.04)
            }
        }))
    }

    /// Foreground color for navigation pills (< | > and trailing pill buttons).
    public static var navPillForeground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor.white
            } else {
                return NSColor.labelColor
            }
        }))
    }

    /// Background for navigation pills (< | > and trailing pill buttons).
    public static var navPillBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.08)
            } else {
                return NSColor(white: 0.0, alpha: 0.06)
            }
        }))
    }

    /// Border for navigation pills.
    public static var navPillBorder: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.10)
            } else {
                return NSColor(white: 0.0, alpha: 0.08)
            }
        }))
    }

    /// Inset hairline divider between rows inside a section card.
    public static var rowDivider: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 1.0, alpha: 0.065)
            } else {
                return NSColor(white: 0.0, alpha: 0.08)
            }
        }))
    }

    /// Section header text color (sits outside the card).
    public static var sectionHeaderColor: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 0.72, alpha: 1.0)
            } else {
                return NSColor(white: 0.28, alpha: 1.0)
            }
        }))
    }

    /// Row title color.
    public static var rowTitleColor: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor.white
            } else {
                return NSColor.labelColor
            }
        }))
    }

    /// Row subtitle color.
    public static var rowSubtitleColor: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 0.60, alpha: 1.0)
            } else {
                return NSColor.secondaryLabelColor
            }
        }))
    }

    // MARK: - Radii

    public static let windowCornerRadius: CGFloat = 26
    public static let detailCardRadius: CGFloat = 22
    public static let sectionCardRadius: CGFloat = 16
    public static let iconTileRadius: CGFloat = 5
    /// Proportional squircle corner radius for icon tiles (e.g. 5pt for 20px, 9pt for 40px, 11pt for 50px).
    public static func iconTileRadius(for size: CGFloat) -> CGFloat {
        max(5, round(size * 0.225))
    }
    public static let navPillRadius: CGFloat = 14
    public static let sidebarSelectionRadius: CGFloat = 8
    public static let searchCapsuleRadius: CGFloat = 14

    // MARK: - Spacing & Dimensions

    public static let sidebarWidth: CGFloat = 216
    public static let sidebarRowPitch: CGFloat = 28
    public static let sidebarGroupSpacing: CGFloat = 14
    public static let detailCardInset: CGFloat = 8
    public static let iconTileSize: CGFloat = 20
    public static let sectionCardPaddingH: CGFloat = 14
    public static let sectionCardPaddingV: CGFloat = 8
    public static let dividerInsetLeading: CGFloat = 42

    // MARK: - Icon Tile Colors

    /// Stable, sensible per-page icon tile colors matching macOS system settings.
    public static func iconTileColor(for page: SettingsPage) -> Color {
        switch page {
        case .general:
            return SettingsTint.general
        case .appearance:
            return SettingsTint.appearance
        case .customize:
            return SettingsTint.customize
        case .shortcuts:
            return SettingsTint.shortcuts
        case .appRules:
            return SettingsTint.appRules
        case .store:
            return SettingsTint.store
        case .about:
            return SettingsTint.about
        case .ai, .aiNewPreset, .aiPreset:
            return SettingsTint.openClip
        case .customActions, .newCustomAction:
            return SettingsTint.openClip
        case .newGroup, .iconPicker, .addApplication:
            return SettingsTint.openClip
        case .builtinAction(let id):
            return SettingsTint.openClip
        case .extensionPackage(let id):
            return SettingsTint.extensionTint(for: id)
        case .action(let id):
            return SettingsTint.openClip
        }
    }

    /// Stable color for specific builtin and common action IDs.
    public static func iconTileColor(forActionID id: String) -> Color {
        let lower = id.lowercased()
        if lower.contains("copy") {
            return Color(red: 0.05, green: 0.72, blue: 0.85) // Cyan
        } else if lower.contains("cut") {
            return Color(red: 0.93, green: 0.28, blue: 0.60) // Pink
        } else if lower.contains("paste") {
            return Color(red: 0.10, green: 0.74, blue: 0.66) // Teal
        } else if lower.contains("search") {
            return Color(red: 0.23, green: 0.51, blue: 0.96) // Blue
        } else if lower.contains("calc") {
            return Color(red: 0.96, green: 0.62, blue: 0.05) // Amber / Gold
        } else if lower.contains("define") || lower.contains("dict") {
            return Color(red: 0.93, green: 0.72, blue: 0.05) // Yellow
        } else if lower.contains("link") || lower.contains("url") {
            return Color(red: 0.08, green: 0.75, blue: 0.52) // Emerald Green
        } else if lower.contains("finder") || lower.contains("reveal") {
            return Color(red: 0.05, green: 0.55, blue: 0.82) // Navy / Cerulean
        } else if lower.contains("event") || lower.contains("cal") {
            return Color(red: 0.15, green: 0.78, blue: 0.40) // Fresh Green
        } else if lower.contains("ai") {
            return Color(red: 0.48, green: 0.36, blue: 0.96) // Indigo
        } else if lower.contains("completion") {
            return Color(red: 0.68, green: 0.35, blue: 0.98) // Purple
        }

        // Deterministic fallback based on hash
        var hash = 0
        for byte in id.utf8 {
            hash = (hash &* 31 &+ Int(byte)) % 360
        }
        return Color(hue: Double(hash) / 360.0, saturation: 0.75, brightness: 0.88)
    }

    /// Color for an SF Symbol used in settings rows.
    public static func iconTileColor(forSystemImage image: String) -> Color {
        let lower = image.lowercased()
        if lower.contains("paint") || lower.contains("brush") || lower.contains("palette") {
            return SettingsTint.appearance // Charcoal / Appearance
        } else if lower.contains("gear") {
            return SettingsTint.general // System Gray
        } else if lower.contains("slider") {
            return SettingsTint.customize // Purple
        } else if lower.contains("key") || lower.contains("command") || lower.contains("keyboard") {
            return Color(red: 0.98, green: 0.52, blue: 0.12) // System Orange
        } else if lower.contains("checklist") || lower.contains("rules") {
            return SettingsTint.appRules // Blue
        } else if lower.contains("bag") || lower.contains("cart") {
            return SettingsTint.store // App Store Blue
        } else if lower.contains("question") || lower.contains("info") {
            return SettingsTint.about // System Gray
        } else if lower.contains("shield") || lower.contains("lock") || lower.contains("check") {
            return Color(red: 0.20, green: 0.78, blue: 0.42) // Green
        } else if lower.contains("sparkle") {
            return Color(red: 0.48, green: 0.36, blue: 0.96) // Indigo
        } else if lower.contains("cursor") || lower.contains("mouse") {
            return Color(red: 0.12, green: 0.56, blue: 0.98) // Sky Blue
        } else if lower.contains("hand") || lower.contains("tap") {
            return Color(red: 0.98, green: 0.46, blue: 0.09) // Orange
        } else if lower.contains("folder") {
            return Color(red: 0.05, green: 0.72, blue: 0.85) // Cyan
        } else if lower.contains("menubar") || lower.contains("dock") {
            return Color(red: 0.30, green: 0.65, blue: 0.98) // Light Blue
        } else if lower.contains("clockwise") || lower.contains("update") || lower.contains("download") {
            return Color(red: 0.10, green: 0.74, blue: 0.66) // Teal
        } else if lower.contains("bell") {
            return Color(red: 0.96, green: 0.62, blue: 0.05) // Amber
        } else if lower.contains("globe") || lower.contains("link") || lower.contains("safari") {
            return Color(red: 0.12, green: 0.56, blue: 0.98) // Safari / Web Blue
        } else if lower.contains("quote") {
            return Color(red: 0.20, green: 0.78, blue: 0.42) // Emerald Green
        } else if lower.contains("terminal") {
            return Color(red: 0.48, green: 0.36, blue: 0.96) // Terminal Purple
        } else if lower.contains("book") {
            return Color(red: 0.98, green: 0.45, blue: 0.09) // Orange
        } else if lower.contains("trash") || lower.contains("delete") {
            return Color(red: 0.92, green: 0.26, blue: 0.21) // Red
        } else if lower.contains("shippingbox") || lower.contains("package") {
            return Color(red: 0.70, green: 0.45, blue: 0.20) // Amber Brown
        } else if lower.contains("exclamationmark") || lower.contains("warning") {
            return Color(red: 0.98, green: 0.46, blue: 0.09) // Orange
        } else if lower.contains("calendar") || lower.contains("event") {
            return Color(red: 0.15, green: 0.78, blue: 0.40) // Fresh Green
        } else if lower.contains("textformat") || lower.contains("font") {
            return Color(red: 0.10, green: 0.74, blue: 0.66) // System Teal
        } else if lower.contains("rectangle.split") || lower.contains("split") {
            return Color(red: 0.35, green: 0.34, blue: 0.84) // System Indigo
        } else if lower.contains("app.dashed") || lower.contains("dashed") {
            return Color(red: 0.65, green: 0.35, blue: 0.95) // System Purple
        } else if lower.contains("magnifyingglass") || lower.contains("search") {
            return Color(red: 0.05, green: 0.52, blue: 0.98) // System Blue
        } else if lower.contains("arrow.turn") || lower.contains("finished") || lower.contains("delivery") {
            return Color(red: 0.20, green: 0.78, blue: 0.42) // System Green
        } else if lower.contains("doc") || lower.contains("file") {
            return Color(red: 0.54, green: 0.54, blue: 0.58) // Gray
        } else if lower.contains("arrow") {
            return Color(red: 0.55, green: 0.45, blue: 0.85) // Slate Purple
        } else if lower.contains("sun") || lower.contains("moon") || lower.contains("circle") {
            return Color(red: 0.45, green: 0.45, blue: 0.50) // Slate
        }

        return SettingsTint.openClip
    }
}

// MARK: - Liquid Glass Modifiers

public extension View {
    /// Renders a liquid glass capsule with frosted blur on macOS 26+, or nav pill background fallback.
    @ViewBuilder
    func settingsGlassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(macOS 26.0, *) {
            self
                .background(
                    Capsule()
                        .fill(tint ?? SettingsDesignTokens.navPillBackground)
                )
                .background(.ultraThinMaterial, in: .capsule)
                .glassEffect(
                    tint != nil
                        ? (interactive ? .regular.tint(tint!.opacity(0.4)).interactive() : .regular.tint(tint!.opacity(0.4)))
                        : (interactive ? .regular.interactive() : .regular),
                    in: .capsule
                )
                .overlay(
                    Capsule()
                        .strokeBorder(tint != nil ? tint!.opacity(0.3) : SettingsDesignTokens.navPillBorder, lineWidth: 0.5)
                )
        } else {
            self
                .background(Capsule().fill(tint ?? SettingsDesignTokens.navPillBackground))
                .overlay(Capsule().strokeBorder(tint != nil ? tint!.opacity(0.3) : SettingsDesignTokens.navPillBorder, lineWidth: 0.5))
        }
    }

    /// Renders a liquid glass circle with frosted blur on macOS 26+, or nav pill background fallback.
    @ViewBuilder
    func settingsGlassCircle(tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(macOS 26.0, *) {
            self
                .background(
                    Circle()
                        .fill(tint ?? SettingsDesignTokens.navPillBackground)
                )
                .background(.ultraThinMaterial, in: .circle)
                .glassEffect(
                    tint != nil
                        ? (interactive ? .regular.tint(tint!.opacity(0.4)).interactive() : .regular.tint(tint!.opacity(0.4)))
                        : (interactive ? .regular.interactive() : .regular),
                    in: .circle
                )
                .overlay(
                    Circle()
                        .strokeBorder(tint != nil ? tint!.opacity(0.3) : SettingsDesignTokens.navPillBorder, lineWidth: 0.5)
                )
        } else {
            self
                .background(Circle().fill(tint ?? SettingsDesignTokens.navPillBackground))
                .overlay(Circle().strokeBorder(tint != nil ? tint!.opacity(0.3) : SettingsDesignTokens.navPillBorder, lineWidth: 0.5))
        }
    }
}

