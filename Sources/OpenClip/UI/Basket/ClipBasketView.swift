// ClipBasketView.swift
// OpenClip
//
// Compact pill that expands into a numbered, reorderable stack. All mutations go through the
// shared ClipBasketStore; paste and lifecycle requests go back to ClipBasketManager.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Core

struct ClipBasketContentSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0 || next.height > 0 {
            value = next
        }
    }
}

struct ClipBasketView: View {
    @ObservedObject var store: ClipBasketStore
    let onPasteNext: @MainActor () -> Void
    let onPasteAll: @MainActor () -> Void
    let onPasteItem: @MainActor (UUID) -> Void
    let onClear: @MainActor () -> Void
    let onClose: @MainActor () -> Void
    let onDrag: @MainActor (CGSize, Bool) -> Void
    let onContentSizeChange: @MainActor (CGSize) -> Void

    @Setting(SettingKey.popupTheme) private var selectedTheme
    @Setting(SettingKey.popupThemeColor) private var themeColor
    @Setting(SettingKey.popupScale) private var popupScale
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var isHovering = false
    @State private var isExpandedByClick = false
    @State private var dragTranslation: CGSize = .zero
    @State private var draggedID: UUID?
    @State private var dropTargetID: UUID?

    private var scale: CGFloat { PopupMetrics.scaleMultiplier(for: popupScale) }
    private var isExpanded: Bool { isHovering || isExpandedByClick }
    private var cornerRadius: CGFloat { ClipBasketMetrics.cornerRadius * scale }
    private var rowHeight: CGFloat { ClipBasketMetrics.rowHeight * scale }
    private var listSpacing: CGFloat { 2 * scale }
    private var rowTextSize: CGFloat { 10.5 * scale }

    private var effectiveTheme: String {
        if PopupThemeModel.category(fromStored: selectedTheme) == .glass {
            return "glass"
        }
        return PopupThemeModel.classicToken(
            appearance: themeColor,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var effectiveColorScheme: ColorScheme {
        PopupThemeModel.effectiveScheme(
            appearance: themeColor,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var foreground: Color { PopupThemeModel.restForeground(for: effectiveTheme) }
    private var secondaryForeground: Color { PopupThemeModel.restSecondary(for: effectiveTheme) }
    private var divider: Color { PopupThemeModel.dividerColor(for: effectiveTheme) }

    var body: some View {
        surface
            .popupCardChrome(
                cornerRadius: cornerRadius,
                effectiveTheme: effectiveTheme,
                colorScheme: effectiveColorScheme
            )
            .padding(PopupMetrics.popupShadowInset)
            .environment(\.colorScheme, effectiveColorScheme)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ClipBasketContentSizePreferenceKey.self,
                        value: proxy.size
                    )
                }
            )
            .onPreferenceChange(ClipBasketContentSizePreferenceKey.self) { size in
                MainActor.assumeIsolated {
                    guard size.width > 0, size.height > 0 else { return }
                    onContentSizeChange(size)
                }
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Clip Basket"))
    }

    @ViewBuilder
    private var surface: some View {
        VStack(spacing: 0) {
            if isExpanded {
                header
                Divider()
                    .overlay(divider)
                content
            } else {
                pill
            }
        }
        .frame(width: (isExpanded ? ClipBasketMetrics.expandedWidth : ClipBasketMetrics.collapsedWidth) * scale)
    }

    private var pill: some View {
        HStack(spacing: 8 * scale) {
            countBadge
            Group {
                if store.isEmpty {
                    Text("Basket is empty")
                } else {
                    Text("Next: \(previewText(for: store.items[0]))")
                }
            }
            .font(.system(size: rowTextSize, weight: .regular))
            .foregroundStyle(secondaryForeground)
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 8 * scale, weight: .semibold))
                .foregroundStyle(secondaryForeground)
        }
        .padding(.horizontal, 12 * scale)
        .frame(height: ClipBasketMetrics.collapsedHeight * scale)
        .contentShape(Rectangle())
        .onTapGesture {
            isExpandedByClick = true
        }
        .gesture(windowDragGesture)
    }

    private var header: some View {
        HStack(spacing: 5 * scale) {
            countBadge
            Text("Clip Basket")
                .font(.system(size: rowTextSize, weight: .semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)

            Spacer(minLength: 2)

            Button {
                store.reverse()
            } label: {
                Text(store.order == .fifo ? "FIFO" : "LIFO")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .foregroundStyle(foreground)
                    .padding(.horizontal, 5 * scale)
                    .frame(height: 20 * scale)
                    .background(
                        Capsule(style: .continuous)
                            .fill(divider.opacity(0.55))
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle first-in-first-out or last-in-first-out")

            headerButton(
                systemName: "textformat",
                help: "Paste as Plain Text",
                active: store.pasteAsPlainText
            ) {
                store.setPasteAsPlainText(!store.pasteAsPlainText)
            }

            headerButton(
                systemName: "arrow.uturn.backward",
                help: "Undo Last Removal",
                disabled: !store.canUndo
            ) {
                _ = store.undo()
            }

            Menu {
                Button("Paste All") { onPasteAll() }
                    .disabled(store.joinedText == nil)
                Divider()
                Button("Clear", role: .destructive) { onClear() }
                    .disabled(store.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: 22 * scale, height: 20 * scale)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel(Text("More"))

            headerButton(systemName: "xmark", help: "Close") {
                onClose()
            }
        }
        .padding(.horizontal, 9 * scale)
        .padding(.vertical, 5 * scale)
        .contentShape(Rectangle())
        .gesture(windowDragGesture)
    }

    @ViewBuilder
    private var content: some View {
        if store.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: listSpacing) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        row(index: index, item: item)
                    }
                }
                .padding(.horizontal, 5 * scale)
                .padding(.vertical, 5 * scale)
            }
            .frame(height: listHeight)
        }
    }

    private var listHeight: CGFloat {
        let contentHeight = CGFloat(store.count) * (rowHeight + listSpacing) + 10 * scale
        let reservedForHeader: CGFloat = 34 * scale
        return min(contentHeight, max(ClipBasketMetrics.maxHeight * scale - reservedForHeader, rowHeight))
    }

    private var emptyState: some View {
        VStack(spacing: 5 * scale) {
            Image(systemName: "basket")
                .font(.system(size: 18 * scale, weight: .regular))
                .foregroundStyle(secondaryForeground)
            Text("Basket is empty")
                .font(.system(size: rowTextSize, weight: .medium))
                .foregroundStyle(foreground)
            Text("Select text and choose Add to Basket.")
                .font(.system(size: 9 * scale, weight: .regular))
                .foregroundStyle(secondaryForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14 * scale)
        .padding(.horizontal, 10 * scale)
    }

    private func row(index: Int, item: ClipBasketItem) -> some View {
        ClipBasketRow(
            index: index,
            item: item,
            scale: scale,
            rowHeight: rowHeight,
            foreground: foreground,
            secondaryForeground: secondaryForeground,
            isTargeted: dropTargetID == item.id,
            onRemove: {
                _ = store.pop(id: item.id)
            },
            onPaste: {
                onPasteItem(item.id)
            }
        )
        .onDrag {
            draggedID = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(
            of: [.text],
            isTargeted: Binding(
                get: { dropTargetID == item.id },
                set: { isTargeted in dropTargetID = isTargeted ? item.id : nil }
            )
        ) { _ in
            guard let draggedID, draggedID != item.id else {
                self.draggedID = nil
                dropTargetID = nil
                return false
            }
            store.move(id: draggedID, toIndex: index)
            self.draggedID = nil
            dropTargetID = nil
            return true
        }
    }

    private var countBadge: some View {
        Text(verbatim: "\(store.count)")
            .font(.system(size: 9.5 * scale, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .padding(.horizontal, 5 * scale)
            .frame(minWidth: 18 * scale, minHeight: 17 * scale)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.22))
            )
    }

    private func headerButton(
        systemName: String,
        help: LocalizedStringKey,
        active: Bool = false,
        disabled: Bool = false,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10 * scale, weight: .semibold))
                .foregroundStyle(active ? Color.white : foreground)
                .frame(width: 22 * scale, height: 20 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 5 * scale, style: .continuous)
                        .fill(active ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .help(help)
        .accessibilityLabel(Text(help))
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: ClipBasketMetrics.dragThreshold)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - dragTranslation.width,
                    height: -(value.translation.height - dragTranslation.height)
                )
                dragTranslation = value.translation
                guard delta != .zero else { return }
                onDrag(delta, false)
            }
            .onEnded { _ in
                dragTranslation = .zero
                onDrag(.zero, true)
            }
    }

    private func previewText(for item: ClipBasketItem) -> String {
        switch item.content {
        case .text(let payload):
            let flattened = (payload.plainText ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !flattened.isEmpty else { return String(localized: "Text") }
            if flattened.count > ClipBasketMetrics.maxPreviewCharacters {
                return String(flattened.prefix(ClipBasketMetrics.maxPreviewCharacters)) + "…"
            }
            return flattened
        case .image:
            return String(localized: "Image")
        case .files(let urls):
            if urls.count == 1 {
                return urls[0].lastPathComponent
            }
            return String(format: String(localized: "%lld files"), urls.count)
        }
    }
}

private struct ClipBasketRow: View {
    let index: Int
    let item: ClipBasketItem
    let scale: CGFloat
    let rowHeight: CGFloat
    let foreground: Color
    let secondaryForeground: Color
    let isTargeted: Bool
    let onRemove: @MainActor () -> Void
    let onPaste: @MainActor () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7 * scale) {
            Text(verbatim: "\(index + 1)")
                .font(.system(size: 9 * scale, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(index == 0 ? Color.accentColor : secondaryForeground)
                .frame(width: 16 * scale, height: 16 * scale)

            contentIcon
                .frame(width: 22 * scale, height: 22 * scale)

            VStack(alignment: .leading, spacing: 1 * scale) {
                Text(primaryText)
                    .font(.system(size: 10.5 * scale, weight: index == 0 ? .medium : .regular))
                    .foregroundStyle(foreground)
                    .lineLimit(ClipBasketMetrics.rowMaxTextLines)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 3 * scale) {
                    sourceIcon
                    if let sourceName = item.sourceApp?.localizedName, !sourceName.isEmpty {
                        Text(sourceName)
                            .font(.system(size: 8.5 * scale, weight: .regular))
                            .foregroundStyle(secondaryForeground)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 2)

            if isHovering {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8 * scale, weight: .bold))
                        .foregroundStyle(secondaryForeground)
                        .frame(width: 16 * scale, height: 16 * scale)
                        .background(
                            Circle().fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .help("Remove")
                .accessibilityLabel(Text("Remove"))
            }
        }
        .padding(.horizontal, 6 * scale)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: ClipBasketMetrics.rowCornerRadius * scale, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: ClipBasketMetrics.rowCornerRadius * scale, style: .continuous)
                        .strokeBorder(isTargeted ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            onPaste()
        }
        .help("Double-click to paste")
    }

    private var backgroundColor: Color {
        if isTargeted { return Color.accentColor.opacity(0.12) }
        if index == 0 { return Color.accentColor.opacity(0.09) }
        if isHovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    private var primaryText: String {
        switch item.content {
        case .text(let payload):
            let text = payload.plainText ?? ""
            return text.isEmpty ? String(localized: "Text") : text
        case .image:
            return String(localized: "Image")
        case .files(let urls):
            if urls.count == 1 {
                return urls[0].lastPathComponent
            }
            return String(format: String(localized: "%lld files"), urls.count)
        }
    }

    @ViewBuilder
    private var contentIcon: some View {
        switch item.content {
        case .text:
            Image(systemName: "text.quote")
                .font(.system(size: 12 * scale, weight: .regular))
                .foregroundStyle(secondaryForeground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 5 * scale, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        case .image(let data, _, _, _):
            if let image = NSImage(data: data), image.isValid {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22 * scale, height: 22 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 5 * scale, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 12 * scale, weight: .regular))
                    .foregroundStyle(secondaryForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .files(let urls):
            Image(nsImage: NSWorkspace.shared.icon(forFile: urls.first?.path ?? ""))
                .resizable()
                .frame(width: 18 * scale, height: 18 * scale)
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let bundleID = item.sourceApp?.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .frame(width: 9 * scale, height: 9 * scale)
        }
    }
}
