import SwiftUI
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
                    _ = try await action.perform(context)
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
    
    @ViewBuilder
    private func iconView(for icon: ActionIcon) -> some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
        case .url(_), .local(_):
            Image(systemName: "square.fill")
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
