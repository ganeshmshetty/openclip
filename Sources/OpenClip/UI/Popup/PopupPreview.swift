// PopupPreview.swift
// OpenClip
//
// Static visual preview of the popup bar rendered with a fixed action set
// (Search, Copy, Cut, Paste, Share + AI), mirroring how the real bar will look
// for the currently selected theme. It is intentionally decoupled from the live
// action registry so it always shows the same canonical actions. Used by the
// Preferences Appearance tab.
import SwiftUI
import AppKit
import Core

@MainActor
struct PopupPreview: View {
    /// The canonical action set shown in the preview, independent of what the user
    /// has enabled/reordered in the real popup.
    private static let previewActions: [any Action] = [
        SearchAction(),
        CopyAction(),
        CutAction(),
        PasteAction(),
        AIToolsAction()
    ]

    /// The preview observes its own hover state (and ignores hover entirely), so it
    /// never reacts to — or leaks into — the real popup's shared hover state.
    private static let previewHoverState = PopupHoverState()

    @State private var wallpaperImage: NSImage? = nil

    private var mockContext: ActionContext {
        let app = NSRunningApplication.current
        let context = SelectionContext(
            text: "OpenClip Preview",
            sourceApp: AppIdentity(app),
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: context, modifiers: [])
    }

    @Setting(SettingKey.popupScale) private var popupScale
    @Setting(SettingKey.popupAlignment) private var popupAlignment
    @Setting(SettingKey.popupVerticalPosition) private var popupVerticalPosition

    private var isPlacedAbove: Bool {
        let pos = PopupVerticalPosition(rawValue: popupVerticalPosition) ?? .auto
        return pos != .below
    }

    private var selectionAlignment: PopupBarAlignment {
        PopupBarAlignment(rawValue: popupAlignment) ?? .left
    }

    private var scale: CGFloat {
        PopupMetrics.scaleMultiplier(for: popupScale)
    }

    private var popupBarWidth: CGFloat {
        // Standard width for 5 actions + Command search glyph at current scale.
        220 * scale
    }

    private var buttonCenterInset: CGFloat {
        (PopupMetrics.actionButtonWidth * scale) / 2
    }

    /// Horizontal offset aligning the popup with the text selection anchors:
    /// - Left: First action button aligns with the left I-beam (-36pt).
    /// - Center: Popup center aligns with selection center (+8pt).
    /// - Right: Last action button aligns with the right I-beam (+52pt).
    private var popupOffsetX: CGFloat {
        switch selectionAlignment {
        case .left:
            return -36 + (popupBarWidth / 2) - buttonCenterInset

        case .center:
            return 8

        case .right:
            return 52 - (popupBarWidth / 2) + buttonCenterInset
        }
    }

    private var popupOffsetY: CGFloat {
        isPlacedAbove ? -28 : 28
    }

    private var cardOffsetY: CGFloat {
        isPlacedAbove ? 26 : -26
    }

    private var previewModeStore: PopupModeStore {
        let store = PopupModeStore()
        store.subBarAbove = isPlacedAbove
        return store
    }

    /// An authentic macOS text insertion I-beam cursor with top/bottom serifs, rendered in pure white.
    private var iBeamView: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white)
                .frame(width: 8, height: 2.2)

            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 15.6)

            Capsule()
                .fill(Color.white)
                .frame(width: 8, height: 2.2)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 0.5)
        .frame(width: 9, height: 20)
    }

    @ViewBuilder
    private var wallpaperBackground: some View {
        if let image = wallpaperImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(1.08)
                .blur(radius: 6)
                .overlay(Color.black.opacity(0.15))
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.20, blue: 0.32),
                    Color(red: 0.10, green: 0.12, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(Color.white.opacity(0.04))
        }
    }

    private var documentCard: some View {
        HStack(spacing: 0) {
            Text("OpenClip turns ")
                .foregroundStyle(.primary.opacity(0.75))

            HStack(spacing: 1.5) {
                if selectionAlignment == .left {
                    iBeamView
                }

                Text("selected text")
                    .foregroundStyle(.white)

                if selectionAlignment != .left {
                    iBeamView
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Color.accentColor)
            )

            Text(" into actions.")
                .foregroundStyle(.primary.opacity(0.75))
        }
        .font(.system(size: 13, weight: .regular))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    var body: some View {
        ZStack {
            wallpaperBackground

            documentCard
                .offset(y: cardOffsetY)

            PopupView(
                actions: Self.previewActions,
                context: mockContext,
                hoverState: Self.previewHoverState,
                isStatic: true,
                modeStore: previewModeStore
            ) { _ in }
            .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
            .offset(x: popupOffsetX, y: popupOffsetY)
        }
        .frame(maxWidth: SettingsLayout.contentMaxWidth - 40)
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .task {
            let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let screen = NSScreen.main ?? NSScreen.screens.first,
                      let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
                    return nil
                }
                return NSImage(contentsOf: url)
            }.value
            wallpaperImage = image
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: popupAlignment)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: popupVerticalPosition)
    }
}
