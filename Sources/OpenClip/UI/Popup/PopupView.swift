import SwiftUI

public struct ActionButton: View {
    public let iconName: String
    public let action: () -> Void
    
    public init(iconName: String, action: @escaping () -> Void) {
        self.iconName = iconName
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}

public struct PopupView: View {
    public let actions: [String] = ["doc.on.doc", "magnifyingglass", "link"]
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 12) {
            ForEach(actions, id: \.self) { icon in
                ActionButton(iconName: icon) {
                    print("Action tapped: \(icon)")
                }
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
