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
import Core

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
    @Environment(\.popupEffectiveTheme) private var effectiveTheme
    @FocusState private var isCardFocused: Bool
    @FocusState private var isFollowUpFocused: Bool
    @State private var followUp = ""
    @State private var isChevronHovered = false
    @State private var isCloseHovered = false
    @State private var isDiffHovered = false
    @State private var isCopyHovered = false
    @State private var isPasteHovered = false
    @State private var isDismissHovered = false
    @State private var isPinHovered = false
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
        } else {
            onDismiss()
        }
    }

    /// The follow-up field shows whenever a host can run one and the card is not an error.
    private var showsFollowUp: Bool { onFollowUp != nil && !payload.isError }

    public var body: some View {
        cardChrome {
            ZStack(alignment: .top) {
                bodyScroll

                topBlurOverlay
                    .frame(maxWidth: .infinity, alignment: .top)

                bottomBlurOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                header
                    .frame(maxWidth: .infinity, alignment: .top)

                footer
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                PopupResizeHandles(
                    tint: PopupThemeModel.restForeground(for: effectiveTheme),
                    accessibilityLabel: String(localized: "Resize result card"),
                    onResize: onResize
                )
            }
        }
        .frame(width: dynamicCardWidth, height: dynamicCardHeight)
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
            guard press.modifiers.contains(.command), hasDiff else { return .ignored }
            toggleDiff()
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
    private static let buttonCornerRadius: CGFloat = 8.0

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
                    Image(systemName: "sparkles")
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
                if hasDiff {
                    diffToggle
                }

                pinButton

                closeButton
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.headerHeight)
        .background(headerCapsuleBackground)
        .padding(.horizontal, 12)
        .padding(.top, Self.headerTopPadding)
    }

    private var headerCapsuleBackground: some View {
        let capsule = Capsule(style: .continuous)
        let strokeColor = colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10)
        let tintOpacity: Double = colorScheme == .dark ? 0.08 : 0.05
        let shadow1 = Color.black.opacity(colorScheme == .dark ? 0.26 : 0.14)
        let shadow2 = Color.black.opacity(colorScheme == .dark ? 0.12 : 0.06)

        return capsule
            .fill(.ultraThinMaterial)
            .overlay(capsule.fill(Color.primary.opacity(tintOpacity)))
            .overlay(capsule.stroke(strokeColor, lineWidth: 0.5))
            .shadow(color: shadow1, radius: 6, x: 0, y: 2.5)
            .shadow(color: shadow2, radius: 1, x: 0, y: 0.5)
    }

    // MARK: - Blur Overlays

    private var cardBackgroundColor: Color {
        if effectiveTheme == "glass" {
            return colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.40)
        } else {
            return Color(red: colorScheme == .dark ? 0.18 : 0.94,
                         green: colorScheme == .dark ? 0.18 : 0.94,
                         blue: colorScheme == .dark ? 0.20 : 0.96)
        }
    }

    private var topBlurOverlay: some View {
        let bg = cardBackgroundColor
        return LinearGradient(
            stops: [
                .init(color: bg, location: 0.0),
                .init(color: bg.opacity(0.85), location: 0.60),
                .init(color: bg.opacity(0.0), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: Self.topInset)
        .allowsHitTesting(false)
    }

    private var bottomBlurOverlay: some View {
        let bg = cardBackgroundColor
        return LinearGradient(
            stops: [
                .init(color: bg.opacity(0.0), location: 0.0),
                .init(color: bg.opacity(0.85), location: 0.45),
                .init(color: bg, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: bottomInset + 2)
        .allowsHitTesting(false)
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
                .foregroundColor(showsDiff ? .accentColor : PopupThemeModel.restForeground(for: effectiveTheme).opacity(isDiffHovered ? 0.9 : 0.6))
                .frame(width: 22, height: 22)
                .background(
                    showsDiff ? Color.accentColor.opacity(0.14) : (isDiffHovered ? Color.primary.opacity(0.08) : Color.clear),
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
                .foregroundColor(isPinned ? .accentColor : PopupThemeModel.restForeground(for: effectiveTheme).opacity(isPinHovered ? 0.9 : 0.6))
                .frame(width: 22, height: 22)
                .background(
                    isPinned ? Color.accentColor.opacity(0.14) : (isPinHovered ? Color.primary.opacity(0.08) : Color.clear),
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

    private var maxCardWidth: CGFloat { maxSize?.width ?? PopupMetrics.aiCardIdealWidth }
    private var maxCardHeight: CGFloat { maxSize?.height ?? PopupMetrics.aiCardMaxHeight }

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

    /// The card is as wide as its text needs, never narrower than the minimum and never wider
    /// than the maximum; once user-sized it is exactly the dragged size.
    private var dynamicCardWidth: CGFloat {
        if isUserSized, let maxSize { return maxSize.width }
        return Self.bounded(naturalTextWidth, min: PopupMetrics.aiCardMinWidth, max: maxCardWidth)
    }

    private static func bounded(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), max(maximum, minimum))
    }

    private static let headerHeight: CGFloat = 32.0
    private static let headerTopPadding: CGFloat = 14.0
    private static let gapAfterHeader: CGFloat = 14.0
    private static let topInset: CGFloat = headerTopPadding + headerHeight + gapAfterHeader
    private static let baseBottomInset: CGFloat = 42.0
    private static let followUpFieldHeight: CGFloat = 30.0
    /// Room under the body for the footer: the buttons, plus the follow-up field when shown.
    private var bottomInset: CGFloat {
        Self.baseBottomInset + (showsFollowUp ? Self.followUpFieldHeight + 8 : 0)
    }

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
        return ceil(rect.height) + Self.topInset + bottomInset
    }

    /// The card is as tall as its text needs, never shorter than the minimum and never taller
    /// than the maximum (beyond which the body scrolls); once user-sized it is exactly the dragged size.
    private var dynamicCardHeight: CGFloat {
        if isUserSized, let maxSize { return maxSize.height }
        return Self.bounded(naturalContentHeight, min: PopupMetrics.aiCardMinHeight, max: maxCardHeight)
    }

    // MARK: - Body

    private var bodyScroll: some View {
        ScrollView {
            bodyText
                .font(.system(size: 13.5, weight: .regular))
                .lineSpacing(3.5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
                .padding(.horizontal, Self.horizontalTextInset)
                .padding(.top, Self.topInset)
                .padding(.bottom, bottomInset)
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
        let strokeColor = colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)
        let primaryOpacity: Double = isHovered ? 0.10 : 0.06
        let shadow1 = Color.black.opacity(colorScheme == .dark ? 0.20 : 0.12)
        let shadow2 = Color.black.opacity(colorScheme == .dark ? 0.10 : 0.05)

        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.primary.opacity(primaryOpacity)))
            .overlay(shape.stroke(strokeColor, lineWidth: 0.5))
            .shadow(color: shadow1, radius: 4, x: 0, y: 2)
            .shadow(color: shadow2, radius: 1, x: 0, y: 0.5)
    }

    private func pasteButtonBackground(isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous)
        let accentShadow = Color.accentColor.opacity(colorScheme == .dark ? 0.35 : 0.28)
        let blackShadow = Color.black.opacity(colorScheme == .dark ? 0.20 : 0.10)

        return shape
            .fill(Color.accentColor.opacity(isHovered ? 0.9 : 1.0))
            .shadow(color: accentShadow, radius: 5, x: 0, y: 2)
            .shadow(color: blackShadow, radius: 2, x: 0, y: 1)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if showsFollowUp {
                followUpField
                    .padding(.horizontal, 14)
            }
            // While an answer streams there is nothing final to copy or paste: the buttons go
            // away (their space stays, so the field does not jump) and come back on settle.
            footerButtons
                .opacity(showsResultButtons ? 1 : 0)
                .allowsHitTesting(showsResultButtons)
                .accessibilityHidden(!showsResultButtons)
        }
        .padding(.bottom, 10)
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
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let strokeColor = colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)
        let hasText = !followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 7) {
            if payload.isStreaming {
                // A follow-up in flight: the spinner lives where the sparkles were, so the wait
                // reads as part of the card rather than a new session.
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
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
            if hasText {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.followUpFieldHeight)
        .background(
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)))
                .overlay(shape.stroke(strokeColor, lineWidth: 0.5))
        )
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
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            if !payload.isError {
                resultButtons
            } else {
                Button {
                    onDismiss()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(glassButtonBackground(isHovered: isDismissHovered))
                        .contentShape(RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Dismiss the error (⎋)"))
                .onHover { isDismissHovered = $0 }
            }
        }
        .padding(.horizontal, 14)
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
                HStack(spacing: 5) {
                    Text("Copy")
                    if isCopyPrimary {
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .opacity(0.85)
                    } else {
                        Text("⌘C")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .opacity(0.7)
                    }
                }
                .font(.system(size: 12, weight: isCopyPrimary ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundColor(isCopyPrimary ? .white : PopupThemeModel.restForeground(for: effectiveTheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
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
                    HStack(spacing: 5) {
                        Text("Paste")
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .opacity(0.85)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
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

