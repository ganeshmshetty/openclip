import SwiftUI
import AppKit
import CoreGraphics
import Core

public struct ActionButton: View {
    public let action: any Action
    public let context: ActionContext
    public let onPerform: () -> Void
    
    public init(action: any Action, context: ActionContext, onPerform: @escaping () -> Void) {
        self.action = action
        self.context = context
        self.onPerform = onPerform
    }
    
    public var body: some View {
        Button {
            Task {
                do {
                    let result = try await action.perform(context)
                    handleResult(result)
                } catch {
                    print("Action failed: \(error)")
                }
                onPerform()
            }
        } label: {
            iconView(for: action.icon)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .help(action.title)
    }
    
    private func handleResult(_ result: ActionResult) {
        switch result {
        case .simulatePaste:
            simulateKeyShortcut(keyCode: Constants.vVirtualKey, modifier: .maskCommand) // Cmd+V
        case .showServices(let text):
            let picker = NSSharingServicePicker(items: [text])
            if let window = NSApp.keyWindow ?? NSApp.windows.first, let view = window.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        case .cut(let text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            simulateKeyShortcut(keyCode: Constants.deleteVirtualKey, modifier: []) // Delete
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .copy(let text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .success, .failure, .none:
            break
        }
    }
    
    private func simulateKeyShortcut(keyCode: CGKeyCode, modifier: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let keydown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let keyup = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            keydown.flags = modifier
            keyup.flags = modifier
            keydown.post(tap: .cghidEventTap)
            keyup.post(tap: .cghidEventTap)
        }
    }
    
    @ViewBuilder
    private func iconView(for icon: ActionIcon) -> some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
        case .url(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else if phase.error != nil {
                    Image(systemName: "exclamationmark.triangle")
                } else {
                    ProgressView().scaleEffect(0.5)
                }
            }
        case .local(let url):
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "doc")
            }
        }
    }
}

public struct PopupView: View {
    public let actions: [any Action]
    public let context: ActionContext
    public let onDismiss: () -> Void
    
    public init(actions: [any Action], context: ActionContext, onDismiss: @escaping () -> Void) {
        self.actions = actions
        self.context = context
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            ForEach(actions, id: \.id) { action in
                ActionButton(action: action, context: context, onPerform: onDismiss)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
    }
}
