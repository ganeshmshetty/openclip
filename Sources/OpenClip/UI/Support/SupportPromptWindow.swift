// SupportPromptWindow.swift
// OpenClip
//
// Standalone support window: a thank-you, a star link for the repository, and the sponsor page.
// It is not tied to the Settings window; StarPrompt decides when it may appear.
import AppKit
import SwiftUI

@MainActor
final class SupportPromptWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    private var isProgrammaticClose = false

    init(
        onStar: @escaping () -> Void,
        onSupport: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 368),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Support OpenClip")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self

        let hosting = NSHostingView(rootView: SupportPromptView(
            onStar: onStar,
            onSupport: onSupport,
            onClose: onClose
        ))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hosting
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        guard !isProgrammaticClose else { return }
        onClose()
    }

    func closeProgrammatically() {
        isProgrammaticClose = true
        close()
    }
}

@MainActor
private struct SupportPromptView: View {
    let onStar: () -> Void
    let onSupport: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                Text(String(localized: "Thank you for using OpenClip!"))
                    .font(.system(size: 20, weight: .semibold))
                    .multilineTextAlignment(.center)

                VStack(spacing: 4) {
                    Text(String(localized: "OpenClip is free and open source."))
                    Text(String(localized: "A star on GitHub helps more people find it."))
                    Text(String(localized: "You can support development with a tip."))
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            }

            VStack(spacing: 8) {
                glassActionButton(
                    title: String(localized: "Star on GitHub"),
                    symbol: "star.fill",
                    tint: SettingsTint.openClip.opacity(0.75),
                    hint: String(localized: "Opens the OpenClip repository on GitHub"),
                    action: onStar
                )
                .keyboardShortcut(.defaultAction)

                glassActionButton(
                    title: String(localized: "Support OpenClip"),
                    symbol: "heart.fill",
                    tint: nil,
                    hint: String(localized: "Opens the OpenClip support page"),
                    action: onSupport
                )
            }
            .padding(.top, 28)

            Button(String(localized: "Close"), action: onClose)
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(String(localized: "Close"))
                .padding(.top, 16)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(width: 400, height: 368)
        .background(.thickMaterial)
        .onExitCommand(perform: onClose)
    }

    private func glassActionButton(
        title: String,
        symbol: String,
        tint: Color?,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint == nil ? Color.primary : Color.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .settingsGlassCapsule(tint: tint, interactive: true)
        .accessibilityHint(hint)
    }
}
