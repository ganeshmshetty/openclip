import SwiftUI
import AppKit
import CoreGraphics
import Core

public struct ActionButton: View {
    public let action: any Action
    public let context: ActionContext
    public let onResult: (ActionResult) -> Void
    
    public init(action: any Action, context: ActionContext, onResult: @escaping (ActionResult) -> Void) {
        self.action = action
        self.context = context
        self.onResult = onResult
    }
    
    public var body: some View {
        Button {
            Task {
                do {
                    let result = try await action.perform(context)
                    onResult(result)
                } catch {
                    print("Action failed: \(error)")
                }
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
    public let onResult: (ActionResult) -> Void
    
    public init(actions: [any Action], context: ActionContext, onResult: @escaping (ActionResult) -> Void) {
        self.actions = actions
        self.context = context
        self.onResult = onResult
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            ForEach(actions, id: \.id) { action in
                ActionButton(action: action, context: context, onResult: onResult)
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
