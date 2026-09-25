// ResultCardView.swift
// OpenClip
//
// The native result card rendered in content mode in place of the bar: a header (back chevron,
// producing action's icon or sparkles + title, diff toggle), a scrollable response body
// (error-styled when the action failed), and a footer carrying Close (⎋) plus Copy/Paste (both
// absent on an error card, which offers only Close; Paste also hidden when the target app can't
// paste). Any action whose resolved outcome is text renders here, not just AI presets.
// Paste/Copy are explicit user requests routed through performCardEffect, so an explicit Paste
// always pastes, and both dismiss the popup (Copy like Paste). The panel is key while the card
// shows (Task 14) and the card owns the keys (SwiftUI .onKeyPress): Esc dismisses the card,
// Return pastes, Shift+Return copies, ⌘D toggles the diff — the controller-level key monitor
// stays observation-only in content mode.
// The card is modal-ish by design: it stays up until Copy, Paste or Esc (see
// PopupWindowController.handleEvent), and its header doubles as a drag handle (a SwiftUI
// DragGesture reported to PopupWindowController.handleCardDrag) so it can be moved out of the way
// of the text underneath. Its right edge, bottom edge and bottom-right grip are resize handles
// A follow-up field sits above Copy/Paste: an instruction typed there (⏎) runs AI on the card's
// current text and re-streams the card in place — a second pass over the answer.
// The card never leaves the screen for it: while the follow-up is in flight the previous answer
// stays visible (dimmed until the first chunk, `payload.isRefining`), the field shows a spinner
// and "Refining…" and keeps focus, Copy/Paste are hidden until the answer settles, and Esc
// cancels the refinement (`onCancelFollowUp`) instead of closing.
// (`PopupResizeHandles`, reported the same way to PopupWindowController.handleResize); the size
// they settle on is remembered and, passed back in as `maxSize`, caps the content-driven size
// when the next card opens: a short answer still gets a small card, a long one grows up to the
// maximum and scrolls beyond it. Once the user has dragged a handle (`isUserSized`), the card
// keeps the dragged size verbatim until it closes.
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


/// Phases of a drag on the card's header handle. The card only reports them; the controller owns
/// the panel and does the moving.
///
/// AppKit dragging is not an option here: the panel is borderless (no title bar),
/// `isMovableByWindowBackground` never fires because the SwiftUI hosting view consumes the press,
/// and an `NSViewRepresentable` handle never receives `mouseDown` either — `NSHostingView` answers
/// `hitTest` with itself for the whole card and dispatches through SwiftUI's own gesture system.
/// So the handle is a SwiftUI `DragGesture`, and the move is computed from the absolute cursor
/// position (never the gesture's translation, which would fight the window moving under it).
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
    /// The most room the card may take — the user's remembered or in-progress resize. The card
    /// renders at what its text needs, floored at `aiCardMinWidth` × `aiCardMinHeight` and capped
    /// here; `nil` caps at the defaults (`aiCardIdealWidth` × `aiCardMaxHeight`).
    public let maxSize: CGSize?
    /// True once the user has dragged a resize handle of this card: it then renders at `maxSize`
    /// verbatim — the size they set, whatever the text needs — instead of the content-fitted size.
    public let isUserSized: Bool
    /// Reports a drag of one of the resize handles so the owner can resize the panel and remember
    /// the size. Phases mirror `onDrag`; `.began` is reported exactly once per drag.
    public let onResize: @MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void
    /// True when the card is explicitly pinned via the pin button — suppresses auto-dismiss so
    /// the card stays visible until the user unpins, copies, pastes, or presses Esc.
    public let isPinned: Bool
    /// Called when the user taps the pin button; the owner toggles the pin state.
    public let onPin: @MainActor () -> Void
    /// Runs an instruction typed into the follow-up field on the card's current text (⏎). nil
    /// hides the field (a host without an AI flow).
    public let onFollowUp: (@MainActor (String) -> Void)?
    /// Cancels a follow-up in flight (Esc while the card is refining), restoring the previous
    /// answer. nil means Esc always dismisses.
    public let onCancelFollowUp: (@MainActor () -> Void)?

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
    @State private var isQuickLookHovered = false
    @State private var isDismissHovered = false
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
    /// The diff of `payload.original` → `payload.text`, recomputed only when the payload settles
    /// (never per body evaluation, and never mid-stream on a half-written response).\
    @State private var diffSegments: [TextDiffSegment] = []
    @State private var showsDiff = false
    /// Set once the user works the toggle, so a later payload update can't override their choice.
    @State private var didChooseDiffMode = false
    /// True between the drag gesture crossing its threshold and its end, so `.began` is reported
    /// exactly once per drag.
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
        onCancelFollowUp: (@MainActor () -> Void)? = nil
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

    /// The follow-up field shows whenever a host can run one, the card is not an error,
    /// the payload supports follow-up (AI results), and the result is not a file.
    private var showsFollowUp: Bool { onFollowUp != nil && !payload.isError && payload.canFollowUp && payload.file == nil }

    /// The secondary header controls (diff, pin) rest hidden and fade in when the pointer is over
    /// the card. They stay visible while either is in an active state — diff shown, card pinned —
    /// so the header never hides a state the user set. Back and close are always visible.
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
            // SwiftUI delivers the key here even while the follow-up field is the AppKit first
            // responder (its focus is set by the controller, not through FocusState), so the
            // field's decision applies at this level too: text typed → follow-up; empty → the
            // card's meaning (paste if available, else copy; Shift+Return always copies).
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

    /// Recomputes the diff for the current payload and picks the default view for it: a light edit
    /// (proofread, tone change) opens on the diff, a wholesale rewrite (translate, summarize)
    /// opens on the plain result — the toggle is always there either way. A response still
    /// streaming is never diffed: the comparison would be against a half-written text.
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

    /// The diff as one attributed run stream: removed characters in red with a strikethrough,
    /// added characters in green, everything else in the body's normal colour. Both get a tinted
    /// background so a changed space or newline is still visible.
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
    private static let buttonCornerRadius: CGFloat = 6.0

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
                    .background(
                        isChevronHovered ? Color.primary.opacity(0.08) : Color.clear,
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back to actions")
            .accessibilityLabel("Back to actions")
            .onHover { isChevronHovered = $0 }

            // Everything between the buttons is the drag handle, so the card can be pulled off the
            // text it covers. The handle sits *behind* this row, clear of the two buttons.
            HStack(spacing: 7) {
                if let icon = payload.icon {
                    // The producing action's own icon (bar-resolution: honors user overrides),
                    // so extension results keep their identity in the card.
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

            HStack(spacing: 4) {
                HStack(spacing: 4) {
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
                .background(
                    isCloseHovered ? Color.primary.opacity(0.08) : Color.clear,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Close (⎋)"))
        .accessibilityLabel(String(localized: "Close result card"))
        .onHover { isCloseHovered = $0 }
    }

    /// A small threshold keeps a plain click on the header (which makes the panel key again after
    /// the user worked in another app) from being read as a drag.
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
                .background(
                    showsDiff
                        ? (isDiffHovered ? Color.accentColor : Color.accentColor.opacity(0.85))
                        : (isDiffHovered ? Color.primary.opacity(0.08) : Color.clear),
                    in: Circle()
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
                .background(
                    isPinned
                        ? (isPinHovered ? Color.accentColor : Color.accentColor.opacity(0.85))
                        : (isPinHovered ? Color.primary.opacity(0.08) : Color.clear),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? String(localized: "Unpin — card will dismiss automatically") : String(localized: "Pin — keep card open when moved"))
        .accessibilityLabel(isPinned ? String(localized: "Unpin result card") : String(localized: "Pin result card"))
        .onHover { isPinHovered = $0 }
    }

    // MARK: - Dynamic Dimensions

    /// What the body actually renders — the diff is longer than the result (it keeps the removed
    /// characters), so the card must be measured against it, not against `payload.text`.
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

    /// Sizing calculation for the card width.
    static func cardWidth(naturalTextWidth: CGFloat, showsFollowUp: Bool, isUserSized: Bool, userWidth: CGFloat?) -> CGFloat {
        let minWidth: CGFloat = showsFollowUp ? followUpCardMinWidth : PopupMetrics.aiCardMinWidth
        let maxWidth: CGFloat = userWidth ?? (showsFollowUp ? followUpCardMaxWidth : PopupMetrics.aiCardIdealWidth)
        if isUserSized, let userWidth { return max(userWidth, minWidth) }
        return bounded(naturalTextWidth, min: minWidth, max: max(minWidth, maxWidth))
    }

    /// The width the body would take unwrapped — its longest line plus the text insets — so a
    /// short answer gets a narrow card and a long one fills the maximum.
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

    /// The width required by the header chrome (back chevron, action/sparkle icon, title, diff toggle,
    /// pin button, close button, and horizontal paddings) so the title is never truncated.
    private var naturalHeaderWidth: CGFloat {
        let titleToMeasure = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleToMeasure.isEmpty else { return PopupMetrics.aiCardMinWidth }
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let rect = (titleToMeasure as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font]
        )
        // Padding (14*2=28) + Back (22) + gap (8) + Icon (13) + gap (7) + minSpacer (8)
        let baseChrome: CGFloat = 28 + 22 + 8 + 13 + 7 + 8
        // Right controls: diff (22) + gap (4) + pin (22) + gap (4) + close (22) = 74 with diff; 48 without diff
        let controlsWidth: CGFloat = (hasDiff && payload.file == nil) ? 74 : 48
        return ceil(rect.width) + baseChrome + controlsWidth
    }

    /// The on-screen size of a PDF page: its crop box (what `PDFView` actually displays, which can
    /// be smaller than the media box when trim/bleed marks are present), rotated into display space
    /// so a page stored sideways isn't measured as portrait.
    nonisolated static func displayPageSize(cropBox: CGSize, rotation: Int) -> CGSize {
        rotation % 180 == 0 ? cropBox : CGSize(width: cropBox.height, height: cropBox.width)
    }

    /// Content-driven sizing for image results: balances width and height based on the image's
    /// aspect ratio (so tall screenshots don't become thin slivers and wide banners don't letterbox).
    /// Once the user manually drags the resize handles, the dragged size is honored verbatim.
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

        // Small image / icon (<= 160 pt in both dimensions): compact card
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
            // Portrait / tall (e.g. mobile mockups, vertical screenshots)
            targetHeight = min(380.0, maxAllowedHeight)
            let neededImageWidth = (targetHeight - 142.0) * ratio
            let idealWidth = neededImageWidth + 2 * horizontalTextInset + 32.0
            targetWidth = bounded(idealWidth, min: 320.0, max: 370.0)
        } else if ratio > 1.35 {
            // Landscape / wide (e.g. 16:9, widescreen banners)
            let baseHeight: CGFloat = ratio > 2.0 ? 250.0 : 275.0
            targetHeight = min(baseHeight, maxAllowedHeight)
            let neededImageWidth = (targetHeight - 142.0) * ratio
            let idealWidth = neededImageWidth + 2 * horizontalTextInset + 24.0
            targetWidth = bounded(idealWidth, min: 370.0, max: maxAllowedWidth)
        } else {
            // Square / near-square
            targetWidth = bounded(350.0, min: 340.0, max: maxAllowedWidth)
            targetHeight = bounded(330.0, min: 290.0, max: maxAllowedHeight)
        }

        return CGSize(width: ceil(targetWidth), height: ceil(targetHeight))
    }

    /// The card is as wide as its text needs, never narrower than the minimum and never wider
    /// than the maximum; once user-sized it is exactly the dragged size.
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

    /// The card is as tall as its text needs, never shorter than the minimum and never taller
    /// than the maximum (beyond which the body scrolls); once user-sized it is exactly the dragged size.
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

    /// True for previews backed by a native view that scrolls itself (`PDFView`, `QLPreviewView`).
    /// These must not sit inside the card's outer `ScrollView`.
    private func embedsScrollablePreview(_ file: FileOutputPayload) -> Bool {
        let kind = effectiveFileKind(file)
        return kind == .pdf || kind == .other
    }

    // MARK: - Body

    @ViewBuilder
    private var cardContent: some View {
        Group {
            if let file = payload.file {
                // Embedded previews (PDFKit, Quick Look) own their scrolling, so they are rendered
                // outside the card's outer ScrollView — nesting two scrollers left wheel/trackpad
                // gestures ambiguous between the preview and the card. Text needs the outer scroll
                // (a long file scrolls past the height cap) and an image is scaled to fit.
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

    private func glassButtonBackground(isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous)
        let strokeColor = colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        let fillOpacity: Double = isHovered
            ? (colorScheme == .dark ? 0.18 : 0.12)
            : (colorScheme == .dark ? 0.12 : 0.07)

        return shape
            .fill(Color.primary.opacity(fillOpacity))
            .overlay(shape.stroke(strokeColor, lineWidth: 0.5))
    }

    private func pasteButtonBackground(isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous)
        return shape
            .fill(Color.accentColor.opacity(isHovered ? 0.85 : 1.0))
            .overlay(shape.stroke(Color.white.opacity(0.20), lineWidth: 0.5))
    }

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
        .padding(.horizontal, 14)
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

    /// The instruction field: ⏎ with text runs a follow-up on the card's current text; ⏎ on an
    /// empty field keeps the card's normal meaning (paste, or copy when paste is unavailable).
    private var followUpField: some View {
        let shape = RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous)
        let strokeColor = colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        return HStack(spacing: 6) {
            if payload.isStreaming {
                // A follow-up in flight: spinner on the left.
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            } else if !isTypingFollowUp {
                // Up-arrow on the left in idle state.
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
            // Stays enabled while a refinement streams: a disabled field drops first responder,
            // and with it the Esc that cancels. ⏎ is a no-op meanwhile (`followUpReturn`), so
            // anything typed simply waits for the next follow-up.
            .onKeyPress(.escape) {
                handleEscape()
                return .handled
            }
            // ⏎ arrives as the field's submit (AppKit handles Return in an NSTextField before
            // SwiftUI's key-press path sees it; an `.onKeyPress(.return)` here fell through to
            // the source app). ⇧ is read from the live modifier state, like the composer rows.
            .onSubmit {
                handleFollowUpReturn(shift: NSEvent.modifierFlags.contains(.shift))
            }

            if isTypingFollowUp {
                // Up-arrow submit button on the right when typing.
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

    /// What ⏎ in the follow-up field does. Pure, so the decision table is unit-testable without
    /// hosting the card.
    enum FollowUpReturn: Equatable {
        case nothing
        case paste
        case copy
        case followUp(String)
    }

    /// Nothing typed: ⏎ keeps the card's meaning (paste; copy when paste is unavailable or with
    /// ⇧). Text typed: a follow-up, once the current answer has settled.
    static func followUpReturn(text: String, isStreaming: Bool, canPaste: Bool?, shift: Bool) -> FollowUpReturn {
        // While a refinement streams the card is busy: ⏎ neither pastes a half-written answer
        // nor queues another follow-up.
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
                        .padding(.vertical, 5)
                        .background(glassButtonBackground(isHovered: isDismissHovered))
                        .contentShape(RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Dismiss the error (⎋)"))
                .onHover { isDismissHovered = $0 }
            }
        }
    }

    @ViewBuilder
    private var fileButtons: some View {
        Button {
            onCopy()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10.5, weight: .medium))
                Text(String(localized: "Copy File"))
                    .font(.system(size: 11.5, weight: .medium))
                Text("⌘C")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(glassButtonBackground(isHovered: isCopyHovered))
            .contentShape(RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(String(localized: "Copy the file to the clipboard and close (⌘C)"))
        .accessibilityLabel("Copy file and close")
        .onHover { isCopyHovered = $0 }

        Button {
            (onSave ?? onPaste)()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(localized: "Save"))
                    .font(.system(size: 11.5, weight: .semibold))
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .opacity(0.9)
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(pasteButtonBackground(isHovered: isSaveHovered))
            .contentShape(RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(String(localized: "Save the file to your configured save location and close (⏎)"))
        .accessibilityLabel("Save file and close")
        .onHover { isSaveHovered = $0 }
    }

    /// Renders the file result by kind: an inline image, an inline PDF, inline text, or the
    /// Quick Look view with a caption. Falls back to the generic icon card when a preview can't
    /// be produced, so a file result is never blank.
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
                    // Drag-out lives on the caption for embedded previews: a drag starting on the
                    // page belongs to the preview's own gestures (e.g. PDF text selection).
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
                // Embedded previews sit outside the card's ScrollView, so the preview yields height
                // to the card instead of overflowing it (a floor of 140 — safe inside a scroller —
                // would clip the caption at the minimum card size).
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
                .background(glassButtonBackground(isHovered: isQuickLookHovered))
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

    @ViewBuilder
    private func copyButtonBackground(isHovered: Bool) -> some View {
        if isCopyPrimary {
            pasteButtonBackground(isHovered: isHovered)
        } else {
            glassButtonBackground(isHovered: isHovered)
        }
    }

    private var isCopyPrimary: Bool {
        canPaste == false
    }

    /// Copy / Paste — the answers that consume the result. Absent on an error card, which only
    /// offers Close.
    @ViewBuilder
    private var resultButtons: some View {
        Group {
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
                .foregroundColor(isCopyPrimary ? Color.white : PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(copyButtonBackground(isHovered: isCopyHovered))
                .contentShape(RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous))
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
                    .padding(.vertical, 5)
                    .background(pasteButtonBackground(isHovered: isPasteHovered))
                    .contentShape(RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous))
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
    /// Makes a file preview a drag source for its underlying file.
    func fileExportDrag(_ url: URL) -> some View {
        self
            .draggable(url)
            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
    }
}
