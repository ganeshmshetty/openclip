// ContextualActionsPopoverView.swift
// OpenClip
//
// Mini popover for configuring which detection-capable actions are allowed to be prioritized contextually.
import SwiftUI
import Core

@MainActor
struct ContextualActionsPopoverView: View {
    @Setting(SettingKey.disabledContextualActionIDs) private var disabledActionIDs
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared

    private var eligibleActions: [any Action] {
        coordinator.actions.filter { $0.isContextual }
    }

    private var listHeight: CGFloat {
        let estimatedRowHeight: CGFloat = 32
        let total = CGFloat(eligibleActions.count) * estimatedRowHeight
        return min(max(total, 32), 240)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Toggle Actions"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SettingsDesignTokens.rowTitleColor)

            Divider()

            if eligibleActions.isEmpty {
                Text(String(localized: "No actions with detection rules found."))
                    .font(.caption)
                    .foregroundStyle(SettingsDesignTokens.secondaryText)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 8) {
                        ForEach(eligibleActions, id: \.id) { action in
                            actionRow(action)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: listHeight)
                .scrollIndicators(.automatic)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func actionRow(_ action: any Action) -> some View {
        let isActionPrioritized = Binding<Bool>(
            get: { !disabledActionIDs.contains(action.id) },
            set: { enabled in
                var updated = disabledActionIDs
                if enabled {
                    updated.remove(action.id)
                } else {
                    updated.insert(action.id)
                }
                disabledActionIDs = updated
            }
        )

        let presentation = customizationManager.presented(action, surface: .table)

        return HStack(alignment: .center, spacing: 10) {
            ActionIconView(icon: presentation.icon, size: 15)
                .frame(width: 18, height: 18, alignment: .center)
                .foregroundStyle(.secondary)

            Text(presentation.title)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(SettingsDesignTokens.rowTitleColor)
                .lineLimit(1)

            Spacer(minLength: 8)

            Toggle("", isOn: isActionPrioritized)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(String(localized: "Prioritize \(presentation.title)"))
        }
    }
}
