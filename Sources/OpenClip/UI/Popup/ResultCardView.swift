// ResultCardView.swift
// OpenClip
//
// The native result card shown in content mode in place of the bar. It stays up until Copy, Paste
// or Esc (see PopupWindowController.handleEvent). Its header is a drag handle and its edges are
// resize handles; the size the user settles on caps the content-driven size when the next card opens.
// A follow-up field re-streams the answer in place; the previous answer stays visible while it runs.
import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import Core
import SDWebImageSVGCoder

private struct FilePreviewMetadata {
    var image: NSImage?
    var icon: NSImage?
    var sizeText = ""
    var typeText = ""
    var text: String?
    var textFailed = false
    var textTruncated = false
    var pageSize: CGSize?
    var pdfFailed = false
}

// MARK: - Card Drag


/// Drag phases from the card or search header. The views only report them; the controller moves the
/// panel. A SwiftUI `DragGesture` drives it because AppKit dragging never receives the press in this
/// borderless hosting view, and the move uses the absolute cursor position, not the gesture translation.
public enum ResultCardDragPhase: Sendable {
    case began
    case changed
    case ended
}

// MARK: - Result Card

public struct ResultCardView: View {
    public let payload: ResultCardPayload
    /// Paste availability of the target app (from the AX probe); `false` hides the Paste button.
    public let canPaste: Bool?
    public let onExit: @MainActor () -> Void
    /// Esc: closes the card outright (the popup goes away) rather than falling back to the bar.
    public let onDismiss: @MainActor () -> Void
    public let onPaste: @MainActor () -> Void
    public let onCopy: @MainActor () -> Void
    public let onSave: (@MainActor () -> Void)?
    /// Reports a drag of the header handle so the owner can move the panel.
    public let onDrag: @MainActor (ResultCardDragPhase) -> Void
    /// The most room the card may take (the user's remembered resize); `nil` caps at the defaults.
    public let maxSize: CGSize?
    /// True once the user has dragged a resize handle: the card then renders at `maxSize` verbatim.
    public let isUserSized: Bool
    /// Reports a drag of one of the resize handles so the owner can resize the panel and remember
    /// the size. Phases mirror `onDrag`; `.began` is reported exactly once per drag.
    public let onResize: @MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void
    /// Pinned cards skip auto-dismiss until unpinned, copied, pasted or closed with Esc.
    public let isPinned: Bool
    public let onPin: @MainActor () -> Void
    /// Runs a follow-up instruction on the card's current text. nil hides the field.
    public let onFollowUp: (@MainActor (String) -> Void)?
    /// Cancels a follow-up in flight (Esc while refining). nil means Esc always dismisses.
    public let onCancelFollowUp: (@MainActor () -> Void)?
    /// Steps to an earlier (-1) or later (+1) result. nil hides the switcher.
    public let onStepVersion: (@MainActor (Int) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.popupEffectiveTheme) private var environmentEffectiveTheme
    @Setting(SettingKey.popupTheme) private var selectedTheme
    @Setting(SettingKey.popupThemeColor) private var themeColor

    private var effectiveTheme: String {
        if !environmentEffectiveTheme.isEmpty {
            return environmentEffectiveTheme
        }
        let category = PopupThemeModel.category(fromStored: selectedTheme)
        if category == .glass { return "glass" }
        return PopupThemeModel.classicToken(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }
    @FocusState private var isCardFocused: Bool
    @FocusState private var isFollowUpFocused: Bool
    @State private var followUp = ""
    @State private var isChevronHovered = false
    @State private var isCloseHovered = false
    @State private var isDiffHovered = false
    @State private var isCopyHovered = false
    @State private var isPasteHovered = false
    @State private var isSaveHovered = false
    @State private var isDismissHovered = false
    @State private var isQuickLookHovered = false
    @State private var isPinHovered = false
    @State private var isCardHovered = false
    @State private var previewImage: NSImage?
    @State private var fileIconImage: NSImage?
    @State private var fileMetadataSize = ""
    @State private var fileMetadataType = ""
    @State private var hasAttemptedImageLoad = false
    @State private var previewFileText: String?
    @State private var previewFileTextFailed = false
    @State private var previewFileTruncated = false
    @State private var previewPDFPageSize: CGSize?
    @State private var previewPDFLoadFailed = false
    /// Diff of `payload.original` → `payload.text`, recomputed when the payload settles, not mid-stream.
    @State private var diffSegments: [TextDiffSegment] = []
    @State private var showsDiff = false
    /// Set once the user works the toggle, so a later payload update can't override their choice.
    @State private var didChooseDiffMode = false
    /// Makes `.began` fire once per drag.
    @State private var isDraggingCard = false

    public init(
        payload: ResultCardPayload,
        canPaste: Bool? = nil,
        maxSize: CGSize? = nil,
        isUserSized: Bool = false,
        isPinned: Bool = false,
        onExit: @escaping @MainActor () -> Void,
        onDismiss: (@MainActor () -> Void)? = nil,
        onPaste: @escaping @MainActor () -> Void,
        onCopy: @escaping @MainActor () -> Void,
        onSave: (@MainActor () -> Void)? = nil,
        onDrag: @escaping @MainActor (ResultCardDragPhase) -> Void = { _ in },
        onResize: @escaping @MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void = { _, _ in },
        onPin: @escaping @MainActor () -> Void = {},
        onFollowUp: (@MainActor (String) -> Void)? = nil,
        onCancelFollowUp: (@MainActor () -> Void)? = nil,
        onStepVersion: (@MainActor (Int) -> Void)? = nil
    ) {
        self.payload = payload
        self.canPaste = canPaste
        self.maxSize = maxSize
        self.isUserSized = isUserSized
        self.isPinned = isPinned
        self.onExit = onExit
        self.onDismiss = onDismiss ?? onExit
        self.onPaste = onPaste
        self.onCopy = onCopy
        self.onSave = onSave
        self.onDrag = onDrag
        self.onResize = onResize
        self.onPin = onPin
        self.onFollowUp = onFollowUp
        self.onCancelFollowUp = onCancelFollowUp
        self.onStepVersion = onStepVersion
    }

    /// Esc while a follow-up streams cancels it and keeps the card; otherwise it dismisses.
    static func escapeCancelsFollowUp(isStreaming: Bool, canCancel: Bool) -> Bool {
        isStreaming && canCancel
    }

    private func handleEscape() {
        if Self.escapeCancelsFollowUp(isStreaming: payload.isStreaming, canCancel: onCancelFollowUp != nil) {
            onCancelFollowUp?()
        } else if !followUp.isEmpty {
            followUp = ""
        } else {
            QuickLookPresenter.shared.close()
            onDismiss()
        }
    }

    private var showsFollowUp: Bool { onFollowUp != nil && !payload.isError && payload.canFollowUp && payload.file == nil }

    /// Diff and pin rest hidden until hover, but stay visible while active so a set state is never hidden.
    private var revealsSecondaryChrome: Bool {
        isCardHovered || showsDiff || isPinned
    }

    public var body: some View {
        cardChrome {
            ZStack(alignment: .top) {
                cardContent

                PopupResizeHandles(
                    tint: PopupThemeModel.restForeground(for: effectiveTheme),
                    accessibilityLabel: String(localized: "Resize result card"),
                    onResize: onResize
                )
            }
        }
        .frame(width: dynamicCardWidth, height: dynamicCardHeight)
        .onHover { isCardHovered = $0 }
        .focusable()
        .focusEffectDisabled()
        .focused($isCardFocused)
        .onAppear {
            if showsFollowUp { isFollowUpFocused = true } else { isCardFocused = true }
            refreshDiff()
        }
        .onChange(of: payload) { _, _ in
            refreshDiff()
        }
        .onKeyPress(.escape) {
            handleEscape()
            return .handled
        }
        .onKeyPress(keys: ["d"], phases: .down) { press in
            guard press.modifiers.contains(.command), hasDiff, payload.file == nil else { return .ignored }
            toggleDiff()
            return .handled
        }
        .onKeyPress(keys: ["z"], phases: .down) { press in
            guard press.modifiers.contains(.command), showsVersionSwitcher else { return .ignored }
            onStepVersion?(press.modifiers.contains(.shift) ? 1 : -1)
            return .handled
        }
        .onKeyPress(keys: ["s"], phases: .down) { press in
            guard press.modifiers.contains(.command), payload.file != nil else { return .ignored }
            (onSave ?? onPaste)()
            return .handled
        }
        .onKeyPress(keys: ["c"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            // Nothing final to copy while an answer streams.
            guard showsResultButtons else { return .handled }
            onCopy()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            if payload.file != nil {
                (onSave ?? onPaste)()
                return .handled
            }
            // SwiftUI sees Return even while the follow-up field is first responder, so apply its rules here too.
            if showsFollowUp {
                handleFollowUpReturn(shift: press.modifiers.contains(.shift))
            } else if canPaste == false || press.modifiers.contains(.shift) {
                onCopy()
            } else {
                onPaste()
            }
            return .handled
        }
        .onDisappear {
            QuickLookPresenter.shared.close()
        }
    }

    // MARK: Diff

    private var hasDiff: Bool { !diffSegments.isEmpty }

    /// Picks the default view: light edits open on the diff, wholesale rewrites on the plain result.
    /// A streaming response is never diffed.
    private func refreshDiff() {
        guard !payload.isError, !payload.isStreaming,
              let original = payload.original else {
            diffSegments = []
            showsDiff = false
            return
        }
        let source = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TextDiff.isMeaningfulEdit(from: source, to: result) else {
            diffSegments = []
            showsDiff = false
            return
        }
        let segments = TextDiff.segments(from: source, to: result)
        diffSegments = segments
        if !didChooseDiffMode {
            showsDiff = true
        }
    }

    private func toggleDiff() {
        didChooseDiffMode = true
        showsDiff.toggle()
    }

    private var insertionColor: Color {
        colorScheme == .dark ? Color(red: 0.35, green: 0.82, blue: 0.50) : Color(red: 0.11, green: 0.53, blue: 0.24)
    }

    private var deletionColor: Color {
        colorScheme == .dark ? Color(red: 0.98, green: 0.47, blue: 0.47) : Color(red: 0.74, green: 0.15, blue: 0.15)
    }

    /// Removed text is red with strikethrough, added text green; both are tinted so changed whitespace shows.
    private var diffAttributedText: AttributedString {
        var output = AttributedString()
        for segment in diffSegments {
            var run = AttributedString(segment.text)
            switch segment.kind {
            case .equal:
                run.foregroundColor = Color.primary.opacity(0.85)
            case .insert:
                run.foregroundColor = insertionColor
                run.backgroundColor = insertionColor.opacity(colorScheme == .dark ? 0.20 : 0.14)
            case .delete:
                run.foregroundColor = deletionColor
                run.backgroundColor = deletionColor.opacity(colorScheme == .dark ? 0.20 : 0.12)
                run.strikethroughStyle = Text.LineStyle.single
            }
            output.append(run)
        }
        return output
    }

    // MARK: - Chrome

    private static let cardCornerRadius: CGFloat = PopupMetrics.cardCornerRadius
    private static let buttonCornerRadius: CGFloat = PopupMetrics.footerButtonCornerRadius

    private func cardChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .popupCardChrome(cornerRadius: Self.cardCornerRadius, effectiveTheme: effectiveTheme, colorScheme: colorScheme)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                onExit()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isChevronHovered ? .primary : PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.65))
                    .frame(width: 22, height: 22)
                    .popupHeaderButtonChrome(
                        effectiveTheme: effectiveTheme,
                        colorScheme: colorScheme,
                        isHovered: isChevronHovered
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back to actions")
            .accessibilityLabel("Back to actions")
            .onHover { isChevronHovered = $0 }

            // Drag handle: everything between the two buttons.
            HStack(spacing: 7) {
                if let icon = payload.icon {
                    // The producing action's icon, so extension results keep their identity.
                    ActionIconView(icon: icon, size: 13)
                        .foregroundColor(.accentColor)
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                Text(payload.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(headerDragGesture)
            .help("Drag to move")

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    if hasDiff && payload.file == nil {
                        diffToggle
                    }

                    pinButton
                }
                .opacity(revealsSecondaryChrome ? 1 : 0)
                .allowsHitTesting(revealsSecondaryChrome)
                .animation(.easeOut(duration: 0.15), value: revealsSecondaryChrome)

                closeButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, Self.headerTopPadding)
        .padding(.bottom, 4)
        .frame(height: Self.headerTotalHeight)
    }

    private var closeButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(isCloseHovered ? .primary : PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.65))
                .frame(width: 22, height: 22)
                .popupHeaderButtonChrome(
                    effectiveTheme: effectiveTheme,
                    colorScheme: colorScheme,
                    isHovered: isCloseHovered
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Close (⎋)"))
        .accessibilityLabel(String(localized: "Close result card"))
        .onHover { isCloseHovered = $0 }
    }

    /// A small threshold keeps a plain click (which re-keys the panel) from reading as a drag.
    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                if !isDraggingCard {
                    isDraggingCard = true
                    onDrag(.began)
                }
                onDrag(.changed)
            }
            .onEnded { _ in
                guard isDraggingCard else { return }
                isDraggingCard = false
                onDrag(.ended)
            }
    }

    private var diffToggle: some View {
        Button {
            toggleDiff()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(showsDiff ? .white : PopupThemeModel.restForeground(for: effectiveTheme).opacity(isDiffHovered ? 0.9 : 0.6))
                .frame(width: 22, height: 22)
                .popupHeaderButtonChrome(
                    effectiveTheme: effectiveTheme,
                    colorScheme: colorScheme,
                    isHovered: isDiffHovered,
                    tint: showsDiff ? .accentColor : nil
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(showsDiff ? String(localized: "Show the plain result (⌘D)") : String(localized: "Show what changed (⌘D)"))
        .accessibilityLabel(String(localized: "Toggle change highlighting"))
        .onHover { isDiffHovered = $0 }
    }

    private var pinButton: some View {
        Button {
            onPin()
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isPinned ? .white : PopupThemeModel.restForeground(for: effectiveTheme).opacity(isPinHovered ? 0.9 : 0.6))
                .frame(width: 22, height: 22)
                .popupHeaderButtonChrome(
                    effectiveTheme: effectiveTheme,
                    colorScheme: colorScheme,
                    isHovered: isPinHovered,
                    tint: isPinned ? .accentColor : nil
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? String(localized: "Unpin — card will dismiss automatically") : String(localized: "Pin — keep card open when moved"))
        .accessibilityLabel(isPinned ? String(localized: "Unpin result card") : String(localized: "Pin result card"))
        .onHover { isPinHovered = $0 }
    }

    // MARK: - Dynamic Dimensions

    /// What the body renders; a diff is longer than the result, so measure what is shown.
    private var measuredText: String {
        if showsDiff, hasDiff {
            return diffSegments.map(\.text).joined()
        }
        return payload.text
    }

    private static let horizontalTextInset: CGFloat = 16.0
    private static let bodyFont = NSFont.systemFont(ofSize: 13.5, weight: .regular)
    private static let bodyParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3.5
        return style
    }()

    static let followUpCardMinWidth: CGFloat = 340.0
    static let followUpCardMaxWidth: CGFloat = 400.0

    private var minCardWidth: CGFloat {
        showsFollowUp ? Self.followUpCardMinWidth : PopupMetrics.aiCardMinWidth
    }

    private var maxCardWidth: CGFloat {
        if let userWidth = maxSize?.width {
            return max(userWidth, minCardWidth)
        }
        return showsFollowUp ? Self.followUpCardMaxWidth : PopupMetrics.aiCardIdealWidth
    }
    private var maxCardHeight: CGFloat { maxSize?.height ?? PopupMetrics.aiCardMaxHeight }

    static func cardWidth(naturalTextWidth: CGFloat, showsFollowUp: Bool, isUserSized: Bool, userWidth: CGFloat?) -> CGFloat {
        let minWidth: CGFloat = showsFollowUp ? followUpCardMinWidth : PopupMetrics.aiCardMinWidth
        let maxWidth: CGFloat = userWidth ?? (showsFollowUp ? followUpCardMaxWidth : PopupMetrics.aiCardIdealWidth)
        if isUserSized, let userWidth { return max(userWidth, minWidth) }
        return bounded(naturalTextWidth, min: minWidth, max: max(minWidth, maxWidth))
    }

    /// Longest line plus insets, so a short answer gets a narrow card.
    private var naturalTextWidth: CGFloat {
        let textToMeasure = measuredText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToMeasure.isEmpty else { return 0 }
        let rect = (textToMeasure as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Self.bodyFont, .paragraphStyle: Self.bodyParagraphStyle]
        )
        // A point of slack so SwiftUI's own line breaking never wraps the measured line.
        return ceil(rect.width) + 2 * Self.horizontalTextInset + 1
    }

    /// Width the header chrome needs so the title is never truncated.
    private var naturalHeaderWidth: CGFloat {
        let titleToMeasure = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleToMeasure.isEmpty else { return PopupMetrics.aiCardMinWidth }
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let rect = (titleToMeasure as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font]
        )
        // Padding, back button, icon, gaps, and min spacer.
        let baseChrome: CGFloat = 28 + 22 + 8 + 13 + 7 + 8
        // Right controls: 74 with diff, 48 without.
        let controlsWidth: CGFloat = (hasDiff && payload.file == nil) ? 74 : 48
        return ceil(rect.width) + baseChrome + controlsWidth
    }

    /// On-screen PDF page size: the crop box (what `PDFView` shows), rotated into display space.
    nonisolated static func displayPageSize(cropBox: CGSize, rotation: Int) -> CGSize {
        rotation % 180 == 0 ? cropBox : CGSize(width: cropBox.height, height: cropBox.width)
    }

    /// Sizes an image card from its aspect ratio; a user-dragged size is honored verbatim.
    public static func imageCardSize(
        imageSize: CGSize?,
        userSize: CGSize?,
        isUserSized: Bool
    ) -> CGSize {
        if isUserSized, let userSize {
            return userSize
        }

        let defaultWidth: CGFloat = 370.0
        let defaultHeight: CGFloat = 290.0

        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else {
            if let userWidth = userSize?.width {
                return CGSize(width: max(userWidth, 340.0), height: defaultHeight)
            }
            return CGSize(width: defaultWidth, height: defaultHeight)
        }

        let w = imageSize.width
        let h = imageSize.height

        if w <= 160 && h <= 160 {
            let smallWidth: CGFloat = userSize?.width != nil ? max(userSize!.width, 320.0) : 320.0
            return CGSize(width: smallWidth, height: 240.0)
        }

        let ratio = w / h
        let maxAllowedWidth: CGFloat = userSize?.width != nil ? max(userSize!.width, 460.0) : 460.0
        let maxAllowedHeight: CGFloat = userSize?.height != nil ? max(userSize!.height, 380.0) : 380.0

        let targetWidth: CGFloat
        let targetHeight: CGFloat

        if ratio < 0.85 {
            targetHeight = min(380.0, maxAllowedHeight)
            let neededImageWidth = (targetHeight - 142.0) * ratio
            let idealWidth = neededImageWidth + 2 * horizontalTextInset + 32.0
            targetWidth = bounded(idealWidth, min: 320.0, max: 370.0)
        } else if ratio > 1.35 {
            let baseHeight: CGFloat = ratio > 2.0 ? 250.0 : 275.0
            targetHeight = min(baseHeight, maxAllowedHeight)
            let neededImageWidth = (targetHeight - 142.0) * ratio
            let idealWidth = neededImageWidth + 2 * horizontalTextInset + 24.0
            targetWidth = bounded(idealWidth, min: 370.0, max: maxAllowedWidth)
        } else {
            targetWidth = bounded(350.0, min: 340.0, max: maxAllowedWidth)
            targetHeight = bounded(330.0, min: 290.0, max: maxAllowedHeight)
        }

        return CGSize(width: ceil(targetWidth), height: ceil(targetHeight))
    }

    /// Width the text needs, clamped to the min and max; a user-sized card is exactly the dragged width.
    private var dynamicCardWidth: CGFloat {
        if let file = payload.file {
            switch effectiveFileKind(file) {
            case .image:
                return Self.imageCardSize(
                    imageSize: previewImage?.size,
                    userSize: maxSize,
                    isUserSized: isUserSized
                ).width
            case .pdf:
                return Self.imageCardSize(
                    imageSize: previewPDFPageSize,
                    userSize: maxSize,
                    isUserSized: isUserSized
                ).width
            case .text:
                return Self.cardWidth(
                    naturalTextWidth: fileTextNaturalWidth,
                    showsFollowUp: showsFollowUp,
                    isUserSized: isUserSized,
                    userWidth: maxSize?.width
                )
            case .other:
                if let userWidth = maxSize?.width {
                    return max(userWidth, 340)
                }
                return 370.0
            }
        }
        let neededWidth = isUserSized ? naturalTextWidth : max(naturalTextWidth, naturalHeaderWidth)
        return Self.cardWidth(
            naturalTextWidth: neededWidth,
            showsFollowUp: showsFollowUp,
            isUserSized: isUserSized,
            userWidth: maxSize?.width
        )
    }

    private static let fileTextFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    private var fileTextNaturalWidth: CGFloat {
        let text = (previewFileText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Self.fileTextFont]
        )
        return ceil(rect.width) + 2 * Self.horizontalTextInset + 1
    }

    private var fileTextMeasuredHeight: CGFloat {
        let text = (previewFileText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return PopupMetrics.aiCardMinHeight }
        let availableWidth = dynamicCardWidth - 2 * Self.horizontalTextInset
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Self.fileTextFont]
        )
        return ceil(rect.height) + Self.headerTotalHeight + Self.baseBottomInset + 16.0
    }

    static func bounded(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), max(maximum, minimum))
    }

    private static let headerTopPadding: CGFloat = 8.0
    private static let headerTotalHeight: CGFloat = 44.0
    private static let baseBottomInset: CGFloat = 46.0
    private static let followUpFieldHeight: CGFloat = 28.0

    /// The height the body needs when wrapped at the card's actual width.
    private var naturalContentHeight: CGFloat {
        let textToMeasure = measuredText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToMeasure.isEmpty else { return PopupMetrics.aiCardMinHeight }
        let availableWidth = dynamicCardWidth - 2 * Self.horizontalTextInset
        let rect = (textToMeasure as NSString).boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Self.bodyFont, .paragraphStyle: Self.bodyParagraphStyle]
        )
        return ceil(rect.height) + Self.headerTotalHeight + Self.baseBottomInset + 16.0
    }

    /// Height the text needs, clamped to the min and max (the body scrolls past max); user-sized is verbatim.
    private var dynamicCardHeight: CGFloat {
        if isUserSized, let maxSize { return maxSize.height }
        if let file = payload.file {
            switch effectiveFileKind(file) {
            case .image:
                return Self.imageCardSize(
                    imageSize: previewImage?.size,
                    userSize: maxSize,
                    isUserSized: isUserSized
                ).height
            case .pdf:
                return Self.imageCardSize(
                    imageSize: previewPDFPageSize,
                    userSize: maxSize,
                    isUserSized: isUserSized
                ).height
            case .text:
                return Self.bounded(fileTextMeasuredHeight, min: PopupMetrics.aiCardMinHeight, max: maxCardHeight)
            case .other:
                return 340.0
            }
        }
        return Self.bounded(naturalContentHeight, min: PopupMetrics.aiCardMinHeight, max: maxCardHeight)
    }

    private func effectiveFileKind(_ file: FileOutputPayload) -> FileOutputKind {
        if file.kind == .text, previewFileTextFailed { return .other }
        return file.kind
    }

    /// Native scrolling previews (`PDFView`, `QLPreviewView`) must sit outside the card's `ScrollView`.
    private func embedsScrollablePreview(_ file: FileOutputPayload) -> Bool {
        let kind = effectiveFileKind(file)
        return kind == .pdf || kind == .other
    }

    // MARK: - Body

    @ViewBuilder
    private var cardContent: some View {
        Group {
            if let file = payload.file {
                // Native scrolling previews sit outside the outer ScrollView (nested scrollers make
                // wheel input ambiguous). Text needs the outer scroll; an image scales to fit.
                if embedsScrollablePreview(file) {
                    filePreviewContent(file)
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        filePreviewContent(file)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                ScrollView {
                    bodyText
                        .font(.system(size: 13.5, weight: .regular))
                        .lineSpacing(3.5)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(.horizontal, Self.horizontalTextInset)
                        .padding(.vertical, 8)
                        .draggable(payload.text)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .paletteSafeAreaBar(edge: .top, spacing: 0) {
            header
        }
        .paletteSafeAreaBar(edge: .bottom, spacing: 0) {
            footer
        }
        .frame(height: dynamicCardHeight)
    }

    @ViewBuilder
    private var bodyText: some View {
        if showsDiff, hasDiff {
            Text(diffAttributedText)
        } else {
            Text(payload.text)
                .foregroundColor(payload.isError ? Color.red : (payload.isRefining ? Color.primary.opacity(0.55) : Color.primary))
        }
    }

    // MARK: - Footer

    static func isTyping(text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isTypingFollowUp: Bool {
        Self.isTyping(text: followUp)
    }

    static let followUpMaxWidthCollapsed: CGFloat = 160.0

    private var footer: some View {
        HStack(spacing: 8) {
            if showsFollowUp {
                followUpField
                    .frame(maxWidth: isTypingFollowUp ? .infinity : Self.followUpMaxWidthCollapsed, alignment: .leading)
            }

            if showsVersionSwitcher, !isTypingFollowUp {
                versionSwitcher
            }

            Spacer(minLength: 0)

            if !isTypingFollowUp {
                footerButtons
                    .opacity(showsResultButtons ? 1 : 0)
                    .allowsHitTesting(showsResultButtons)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(PopupMetrics.springOrImmediate(response: 0.28, dampingFraction: 0.82), value: isTypingFollowUp)
        .animation(.easeInOut(duration: 0.15), value: showsResultButtons)
        .padding(.leading, 14)
        // Compact trailing inset; the resize grip only occupies the bottom-right corner.
        .padding(.trailing, 10)
        .padding(.bottom, 6)
        .frame(height: Self.baseBottomInset)
    }

    private var showsResultButtons: Bool {
        Self.showsResultButtons(isStreaming: payload.isStreaming)
    }

    /// Copy / Paste (or Dismiss) are offered only once the card's text has settled.
    static func showsResultButtons(isStreaming: Bool) -> Bool {
        !isStreaming
    }

    private var showsVersionSwitcher: Bool {
        onStepVersion != nil && showsFollowUp && !payload.isStreaming && payload.versionCount > 1
    }

    private var versionSwitcher: some View {
        let tint = PopupThemeModel.restForeground(for: effectiveTheme)
        return HStack(spacing: 2) {
            Button { onStepVersion?(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
            }
            .disabled(payload.versionIndex <= 1)
            .help(String(localized: "Previous result (⌘Z)"))
            .accessibilityLabel(String(localized: "Previous result"))

            Text("\(payload.versionIndex)/\(payload.versionCount)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())

            Button { onStepVersion?(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .disabled(payload.versionIndex >= payload.versionCount)
            .help(String(localized: "Next result (⇧⌘Z)"))
            .accessibilityLabel(String(localized: "Next result"))
        }
        .buttonStyle(.plain)
        .foregroundColor(tint.opacity(0.65))
    }

    private var followUpField: some View {
        let shape = RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous)
        let strokeColor = colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        return HStack(spacing: 6) {
            if payload.isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            } else if !isTypingFollowUp {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.65))
                    .frame(width: 14, height: 14)
                    .transition(.scale.combined(with: .opacity))
            }

            TextField(
                payload.isStreaming ? String(localized: "Refining…") : String(localized: "Follow up…"),
                text: $followUp
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .regular))
            .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
            .focused($isFollowUpFocused)
            // Stays enabled while refining: a disabled field would drop focus and the Esc that cancels.
            .onKeyPress(.escape) {
                handleEscape()
                return .handled
            }
            // ⏎ arrives as onSubmit (AppKit consumes Return first); ⇧ is read from the live modifiers.
            .onSubmit {
                handleFollowUpReturn(shift: NSEvent.modifierFlags.contains(.shift))
            }

            if isTypingFollowUp {
                Button {
                    handleFollowUpReturn(shift: NSEvent.modifierFlags.contains(.shift))
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Send follow-up (⏎)"))
                .accessibilityLabel(String(localized: "Send follow-up"))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, isTypingFollowUp ? 10 : 8)
        .padding(.trailing, isTypingFollowUp ? 6 : 8)
        .frame(height: Self.followUpFieldHeight)
        .background(
            shape
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                .overlay(shape.stroke(strokeColor, lineWidth: 0.5))
        )
        .animation(PopupMetrics.springOrImmediate(response: 0.25, dampingFraction: 0.8), value: isTypingFollowUp)
        .accessibilityLabel(String(localized: "Follow-up instruction"))
    }

    /// Pure decision for ⏎ in the follow-up field, so it is unit-testable without hosting the card.
    enum FollowUpReturn: Equatable {
        case nothing
        case paste
        case copy
        case followUp(String)
    }

    /// Nothing typed: ⏎ keeps the card's meaning (paste, or copy without paste or with ⇧). Typed: a follow-up.
    static func followUpReturn(text: String, isStreaming: Bool, canPaste: Bool?, shift: Bool) -> FollowUpReturn {
        // While streaming, ⏎ neither pastes a half-written answer nor queues another follow-up.
        if isStreaming { return .nothing }
        let instruction = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if instruction.isEmpty {
            return (canPaste == false || shift) ? .copy : .paste
        }
        return .followUp(instruction)
    }

    private func handleFollowUpReturn(shift: Bool) {
        switch Self.followUpReturn(
            text: followUp,
            isStreaming: payload.isStreaming,
            canPaste: canPaste,
            shift: shift
        ) {
        case .nothing:
            break
        case .paste:
            onPaste()
        case .copy:
            onCopy()
        case .followUp(let instruction):
            onFollowUp?(instruction)
            followUp = ""
        }
    }

    private var footerButtons: some View {
        HStack(spacing: 6) {
            if payload.file != nil {
                fileButtons
            } else if !payload.isError {
                resultButtons
            } else {
                Button {
                    onDismiss()
                } label: {
                    Text(String(localized: "Dismiss"))
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .popupFooterButtonChrome(
                            effectiveTheme: effectiveTheme,
                            colorScheme: colorScheme,
                            isHovered: isDismissHovered
                        )
                }
                .buttonStyle(.plain)
                .help(String(localized: "Dismiss the error (⎋)"))
                .onHover { isDismissHovered = $0 }
            }
        }
    }

    @ViewBuilder
    private var fileButtons: some View {
        HStack(spacing: 4) {
            Button {
                onCopy()
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "Copy"))
                        .font(.system(size: 11.5, weight: .medium))
                    Text("⌘C")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
                }
                .lineLimit(1)
                .fixedSize()
                .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .popupFooterButtonChrome(
                    effectiveTheme: effectiveTheme,
                    colorScheme: colorScheme,
                    isHovered: isCopyHovered
                )
            }
            .buttonStyle(.plain)
            .help(String(localized: "Copy the file to the clipboard and close (⌘C)"))
            .accessibilityLabel("Copy file and close")
            .onHover { isCopyHovered = $0 }

            Button {
                (onSave ?? onPaste)()
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "Save"))
                        .font(.system(size: 11.5, weight: .medium))
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .opacity(0.9)
                }
                .lineLimit(1)
                .fixedSize()
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .popupFooterButtonChrome(
                    effectiveTheme: effectiveTheme,
                    colorScheme: colorScheme,
                    isHovered: isSaveHovered,
                    tint: .accentColor
                )
            }
            .buttonStyle(.plain)
            .help(String(localized: "Save the file to your configured save location and close (⏎)"))
            .accessibilityLabel("Save file and close")
            .onHover { isSaveHovered = $0 }
        }
    }

    /// Renders a file result by kind; falls back to the generic icon card so a file result is never blank.
    @ViewBuilder
    private func filePreviewContent(_ file: FileOutputPayload) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            filePreviewBody(file)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.horizontalTextInset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .task(id: file.url) {
            await loadFileMetadata(for: file)
        }
    }

    @ViewBuilder
    private func filePreviewBody(_ file: FileOutputPayload) -> some View {
        switch effectiveFileKind(file) {
        case .image:
            imageFileBody(file)
                .fileExportDrag(file.url)
        case .pdf:
            if previewPDFLoadFailed {
                genericFileBody(file)
                    .fileExportDrag(file.url)
            } else {
                framedPreviewBody {
                    PDFPreviewView(url: file.url)
                } caption: {
                    // Drag-out lives on the caption: a drag on the page belongs to the preview (e.g. PDF text selection).
                    fileCaption(file)
                        .fileExportDrag(file.url)
                }
            }
        case .text:
            textFileBody(file)
                .fileExportDrag(file.url)
        case .other:
            framedPreviewBody {
                QuickLookPreviewView(url: file.url)
            } caption: {
                fileCaption(file)
                    .fileExportDrag(file.url)
            }
        }
    }

    @ViewBuilder
    private func framedPreviewBody<Preview: View, Caption: View>(
        @ViewBuilder preview: () -> Preview,
        @ViewBuilder caption: () -> Caption
    ) -> some View {
        VStack(spacing: 8) {
            preview()
                .frame(maxWidth: .infinity)
                // Yields height to the card; a floor of 140 would clip the caption at minimum size.
                .frame(height: max(60, dynamicCardHeight - Self.headerTotalHeight - Self.baseBottomInset - 52))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
                )
            caption()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func imageFileBody(_ file: FileOutputPayload) -> some View {
        if previewImage != nil || !hasAttemptedImageLoad {
            if let nsImage = previewImage {
                VStack(spacing: 8) {
                    let maxAllowedH = max(80, dynamicCardHeight - Self.headerTotalHeight - Self.baseBottomInset - 32)
                    let maxAllowedW = max(100, dynamicCardWidth - 2 * Self.horizontalTextInset)
                    let isSmall = nsImage.size.width <= 160 && nsImage.size.height <= 160

                    if isSmall {
                        let imgW = min(nsImage.size.width, maxAllowedW)
                        let imgH = min(nsImage.size.height, maxAllowedH)
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07), lineWidth: 1)
                                )
                                .frame(width: max(imgW + 36, 110), height: max(imgH + 28, 86))

                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: imgW, height: imgH)
                        }
                    } else {
                        let imgMaxH = min(nsImage.size.height, maxAllowedH)
                        let imgMaxW = min(nsImage.size.width, maxAllowedW)

                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 6, x: 0, y: 3)
                            .frame(maxWidth: imgMaxW, maxHeight: imgMaxH)
                    }

                    fileCaption(file)
                }
                .frame(maxWidth: .infinity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: 100)
            }
        } else {
            genericFileBody(file)
        }
    }

    private func fileCaption(_ file: FileOutputPayload) -> some View {
        HStack(spacing: 6) {
            Text(file.displayName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
                .lineLimit(1)
                .truncationMode(.middle)

            if !fileMetadataSize.isEmpty {
                Text("•")
                    .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.35))
                Text(fileMetadataSize)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.65))
            }
        }
    }

    @ViewBuilder
    private func textFileBody(_ file: FileOutputPayload) -> some View {
        if let text = previewFileText {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                if previewFileTruncated {
                    Text(String(localized: "Preview truncated"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
                }
            }
        } else if previewFileTextFailed {
            genericFileBody(file)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: 100)
        }
    }

    @ViewBuilder
    private func genericFileBody(_ file: FileOutputPayload) -> some View {
        VStack(spacing: 10) {
            if let icon = fileIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 54, height: 54)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.12), radius: 4, x: 0, y: 2)
            }

            VStack(spacing: 3) {
                Text(file.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 5) {
                    if !fileMetadataType.isEmpty {
                        Text(fileMetadataType)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.65))
                    }

                    if !fileMetadataSize.isEmpty {
                        if !fileMetadataType.isEmpty {
                            Text("•")
                                .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.35))
                        }
                        Text(fileMetadataSize)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.65))
                    }
                }
            }

            Button {
                QuickLookPresenter.shared.toggle(url: file.url)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(String(localized: "Preview"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .popupFooterButtonChrome(
                    effectiveTheme: effectiveTheme,
                    colorScheme: colorScheme,
                    isHovered: isQuickLookHovered
                )
                .contentShape(RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Preview file with Quick Look"))
            .onHover { isQuickLookHovered = $0 }
        }
        .frame(maxWidth: .infinity)
    }

    /// Loads file preview data and metadata without blocking the result-card UI.
    private func loadFileMetadata(for file: FileOutputPayload) async {
        let url = file.url
        let kind = file.kind
        let metadata = await Task.detached(priority: .userInitiated) { () -> FilePreviewMetadata in
            var result = FilePreviewMetadata()

            if kind == .image, let data = try? Data(contentsOf: url), !data.isEmpty {
                result.image = NSImage(data: data) ?? SDImageSVGCoder.shared.decodedImage(with: data, options: nil)
            }

            if kind == .pdf {
                if let document = PDFDocument(url: url), let page = document.page(at: 0) {
                    result.pageSize = Self.displayPageSize(
                        cropBox: page.bounds(for: .cropBox).size,
                        rotation: page.rotation
                    )
                } else {
                    result.pdfFailed = true
                }
            }

            if kind == .text {
                let cap = 100_000
                if let handle = try? FileHandle(forReadingFrom: url) {
                    var data = (try? handle.read(upToCount: cap + 1)) ?? Data()
                    try? handle.close()
                    if data.count > cap {
                        data = data.prefix(cap)
                        result.textTruncated = true
                    }
                    if let decoded = String(data: data, encoding: .utf8) {
                        result.text = decoded
                    } else {
                        result.textFailed = true
                    }
                } else {
                    result.textFailed = true
                }
            }

            result.icon = NSWorkspace.shared.icon(forFile: url.path)

            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useAll]
                formatter.countStyle = .file
                result.sizeText = formatter.string(fromByteCount: size)
            }

            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
                result.typeText = type.localizedDescription ?? type.preferredFilenameExtension?.uppercased() ?? "File"
            } else {
                let ext = url.pathExtension.uppercased()
                result.typeText = ext.isEmpty ? "File" : "\(ext) File"
            }

            return result
        }.value

        self.previewImage = metadata.image
        self.previewPDFPageSize = metadata.pageSize
        self.previewPDFLoadFailed = metadata.pdfFailed
        self.previewFileText = metadata.text
        self.previewFileTextFailed = metadata.textFailed
        self.previewFileTruncated = metadata.textTruncated
        self.fileIconImage = metadata.icon
        self.fileMetadataSize = metadata.sizeText
        self.fileMetadataType = metadata.typeText
        self.hasAttemptedImageLoad = true
    }

    private var isCopyPrimary: Bool {
        canPaste == false
    }

    /// Copy / Paste — the answers that consume the result. Absent on an error card, which only
    /// offers Close.
    @ViewBuilder
    private var resultButtons: some View {
        HStack(spacing: 4) {
            Button {
                onCopy()
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "Copy"))
                        .font(.system(size: 11.5, weight: isCopyPrimary ? .semibold : .medium))
                    if isCopyPrimary {
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .opacity(0.9)
                    } else {
                        Text("⌘C")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
                    }
                }
                .lineLimit(1)
                .fixedSize()
                .foregroundColor(isCopyPrimary ? .white : PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .popupFooterButtonChrome(
                    effectiveTheme: effectiveTheme,
                    colorScheme: colorScheme,
                    isHovered: isCopyHovered,
                    tint: isCopyPrimary ? .accentColor : nil
                )
            }
            .buttonStyle(.plain)
            .help(isCopyPrimary ? String(localized: "Copy the response to the clipboard and close (⏎)") : String(localized: "Copy the response to the clipboard and close (⌘C)"))
            .accessibilityLabel("Copy response and close")
            .onHover { isCopyHovered = $0 }

            if canPaste != false {
                Button {
                    onPaste()
                } label: {
                    HStack(spacing: 4) {
                        Text(String(localized: "Paste"))
                            .font(.system(size: 11.5, weight: .semibold))
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .opacity(0.9)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .popupFooterButtonChrome(
                        effectiveTheme: effectiveTheme,
                        colorScheme: colorScheme,
                        isHovered: isPasteHovered,
                        tint: .accentColor
                    )
                }
                .buttonStyle(.plain)
                .help(String(localized: "Paste the response over the selection (⏎)"))
                .accessibilityLabel("Paste response over selection")
                .onHover { isPasteHovered = $0 }
            }
        }
    }
}

private extension View {
    func fileExportDrag(_ url: URL) -> some View {
        self
            .draggable(url)
            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
    }
}
