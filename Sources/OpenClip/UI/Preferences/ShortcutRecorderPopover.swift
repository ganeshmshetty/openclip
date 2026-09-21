// ShortcutRecorderPopover.swift
// OpenClip
//
// A compact, minimal popover-based keyboard shortcut recorder component for macOS.
// Displays the shortcut in a clean rectangular pill without decorations,
// and opens a small live popover that notes pressed keys in real-time.
import SwiftUI
import AppKit
import KeyboardShortcuts

// MARK: - Shortcut Component

/// A clean rectangular button that displays the assigned shortcut and opens a small recorder popover.
@MainActor
public struct Shortcut: View {
    @Environment(\.colorScheme) private var colorScheme
    public let name: KeyboardShortcuts.Name?
    @Binding public var customShortcut: KeyboardShortcuts.Shortcut?
    public var width: CGFloat
    public var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    @State private var isPopoverOpen: Bool = false
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?

    public init(
        for name: KeyboardShortcuts.Name,
        width: CGFloat = 120,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.name = name
        self._customShortcut = .constant(nil)
        self.width = width
        self.onChange = onChange
    }

    public init(
        shortcut: Binding<KeyboardShortcuts.Shortcut?>,
        width: CGFloat = 120,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.name = nil
        self._customShortcut = shortcut
        self.width = width
        self.onChange = onChange
    }

    private var effectiveShortcut: KeyboardShortcuts.Shortcut? {
        if let currentShortcut {
            return currentShortcut
        }
        if let name {
            return KeyboardShortcuts.getShortcut(for: name)
        }
        return customShortcut
    }

    public var body: some View {
        Button {
            isPopoverOpen = true
        } label: {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if let shortcut = effectiveShortcut {
                    Text(shortcut.description)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Text("Record Shortcut")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(width: width, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        glassBorder,
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06), radius: 2, x: 0, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(ShortcutButtonStyle())
        .onAppear {
            currentShortcut = name != nil ? KeyboardShortcuts.getShortcut(for: name!) : customShortcut
        }
        .popover(isPresented: $isPopoverOpen, arrowEdge: .bottom) {
            ShortcutRecordingPopover(
                onSave: { newShortcut in
                    saveShortcut(newShortcut)
                    isPopoverOpen = false
                },
                onClear: {
                    clearShortcut()
                    isPopoverOpen = false
                },
                onCancel: {
                    isPopoverOpen = false
                }
            )
        }
    }

    private var glassBorder: LinearGradient {
        if isPopoverOpen {
            return LinearGradient(
                colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.25), Color.white.opacity(0.08)]
                : [Color.white.opacity(0.85), Color.black.opacity(0.1)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func saveShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        if let name {
            KeyboardShortcuts.setShortcut(shortcut, for: name)
        } else {
            customShortcut = shortcut
        }
        currentShortcut = shortcut
        onChange?(shortcut)
    }

    private func clearShortcut() {
        saveShortcut(nil)
    }
}

public typealias ShortcutRecorderButton = Shortcut

// MARK: - Shortcut Button Style

private struct ShortcutButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Shortcut Recording Popover View

/// A small, minimal popover that actively notes live modifier presses and key combinations.
@MainActor
public struct ShortcutRecordingPopover: View {
    public let onSave: (KeyboardShortcuts.Shortcut) -> Void
    public let onClear: () -> Void
    public let onCancel: () -> Void

    @State private var activeModifiers: NSEvent.ModifierFlags = []
    @State private var recordedShortcut: KeyboardShortcuts.Shortcut?
    @State private var errorMessage: String? = nil
    @State private var isSuccessFlash: Bool = false
    @State private var pendingSaveWorkItem: DispatchWorkItem? = nil
    @StateObject private var eventMonitor = RecorderEventMonitor()

    public var body: some View {
        VStack(spacing: 10) {
            Text(isSuccessFlash ? "Saved!" : "Press Shortcut")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSuccessFlash ? Color.green : Color.secondary)

            // Minimal Live Keys Row
            HStack(spacing: 4) {
                KeyBox("⌃", isPressed: activeModifiers.contains(.control))
                KeyBox("⌥", isPressed: activeModifiers.contains(.option))
                KeyBox("⇧", isPressed: activeModifiers.contains(.shift))
                KeyBox("⌘", isPressed: activeModifiers.contains(.command))

                if let recorded = recordedShortcut {
                    let key = recorded.description
                        .replacingOccurrences(of: "⌃", with: "")
                        .replacingOccurrences(of: "⌥", with: "")
                        .replacingOccurrences(of: "⇧", with: "")
                        .replacingOccurrences(of: "⌘", with: "")
                    KeyBox(key, isPressed: true, isAccent: true)
                } else {
                    KeyBox("Key", isDashed: true)
                }
            }

            // Error or Help Footnote
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else {
                Text("⎋ Esc to cancel  •  ⌫ to clear")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(width: 220)
        .onAppear {
            eventMonitor.start { event in
                self.processKeyEvent(event)
            }
        }
        .onDisappear {
            pendingSaveWorkItem?.cancel()
            pendingSaveWorkItem = nil
            eventMonitor.stop()
        }
    }

    private func processKeyEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged {
            let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
            withAnimation(.easeInOut(duration: 0.1)) {
                self.activeModifiers = flags
            }
            return nil
        }

        if event.type == .keyDown {
            // Esc: Cancel
            if event.keyCode == 53 {
                pendingSaveWorkItem?.cancel()
                pendingSaveWorkItem = nil
                onCancel()
                return nil
            }

            // Delete / Backspace without modifiers: Clear
            let currentModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if (event.keyCode == 51 || event.keyCode == 117) && currentModifiers.isEmpty {
                pendingSaveWorkItem?.cancel()
                pendingSaveWorkItem = nil
                onClear()
                return nil
            }

            // Must include modifier unless it's a function key
            let isFKey = isFunctionKey(keyCode: Int(event.keyCode))
            guard !currentModifiers.isEmpty || isFKey else {
                withAnimation {
                    self.errorMessage = String(localized: "Include ⌘, ⌥, ⌃, or ⇧")
                }
                return nil
            }

            guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
                return nil
            }

            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                self.recordedShortcut = shortcut
                self.errorMessage = nil
                self.isSuccessFlash = true
            }

            pendingSaveWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                onSave(shortcut)
            }
            self.pendingSaveWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)

            return nil
        }

        return event
    }

    private func isFunctionKey(keyCode: Int) -> Bool {
        switch keyCode {
        case 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90:
            return true
        default:
            return false
        }
    }
}

// MARK: - Key Box

/// A compact rectangular keycap showing only the key symbol.
private struct KeyBox: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    var isPressed: Bool = false
    var isAccent: Bool = false
    var isDashed: Bool = false

    init(
        _ symbol: String,
        isPressed: Bool = false,
        isAccent: Bool = false,
        isDashed: Bool = false
    ) {
        self.symbol = symbol
        self.isPressed = isPressed
        self.isAccent = isAccent
        self.isDashed = isDashed
    }

    var body: some View {
        Text(symbol)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(isPressed || isAccent ? .white : .primary)
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        borderColor,
                        style: StrokeStyle(lineWidth: 1, dash: isDashed ? [3, 2] : [])
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 1, x: 0, y: 1)
            .scaleEffect(isPressed ? 1.06 : 1.0)
            .animation(.spring(response: 0.15, dampingFraction: 0.7), value: isPressed)
    }

    private var backgroundColor: Color {
        if isPressed {
            return Color.accentColor
        }
        if isAccent {
            return Color.accentColor.opacity(0.85)
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.6)
    }

    private var borderColor: Color {
        if isPressed {
            return Color.white.opacity(0.6)
        }
        if isAccent {
            return Color.accentColor
        }
        return colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
    }
}

// MARK: - Event Monitor Helper

@MainActor
private final class RecorderEventMonitor: ObservableObject {
    private var monitor: AnyObject?
    var onEvent: ((NSEvent) -> NSEvent?)?

    func start(onEvent: @escaping (NSEvent) -> NSEvent?) {
        stop()
        self.onEvent = onEvent
        KeyboardShortcuts.isEnabled = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, let onEvent = self.onEvent else { return event }
            return onEvent(event)
        } as AnyObject
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        KeyboardShortcuts.isEnabled = true
    }
}
