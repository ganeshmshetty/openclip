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
// (`PopupResizeHandles`, reported the same way to PopupWindowController.handleResize); the size
// they settle on is remembered and, passed back in as `preferredSize`, replaces the
// content-driven size next time.
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
    /// The size to render at — the user's remembered or in-progress resize. `nil` sizes the card
    /// from its content (`aiCardIdealWidth` wide, height between the min and max card height).
    public let preferredSize: CGSize?
    /// Reports a drag of one of the resize handles so the owner can resize the panel and remember
    /// the size. Phases mirror `onDrag`; `.began` is reported exactly once per drag.
    public let onResize: @MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.popupEffectiveTheme) private var effectiveTheme
    @FocusState private var isCardFocused: Bool
    @State private var isChevronHovered = false
    @State private var isCloseHovered = false
    @State private var isDiffHovered = false
    @State private var isCopyHovered = false
    @State private var isPasteHovered = false
    @State private var isDismissHovered = false
    /// The diff of `payload.original` → `payload.text`, recomputed only when the payload settles
    /// (never per body evaluation, and never mid-stream on a half-written response).
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
        preferredSize: CGSize? = nil,
        onExit: @escaping @MainActor () -> Void,
        onDismiss: (@MainActor () -> Void)? = nil,
        onPaste: @escaping @MainActor () -> Void,
        onCopy: @escaping @MainActor () -> Void,
        onDrag: @escaping @MainActor (ResultCardDragPhase) -> Void = { _ in },
        onResize: @escaping @MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void = { _, _ in }
    ) {
        self.payload = payload
        self.canPaste = canPaste
        self.preferredSize = preferredSize
        self.onExit = onExit
        self.onDismiss = onDismiss ?? onExit
        self.onPaste = onPaste
        self.onCopy = onCopy
        self.onDrag = onDrag
        self.onResize = onResize
    }

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
            isCardFocused = true
            refreshDiff()
        }
        .onChange(of: payload) { _, _ in
            refreshDiff()
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(keys: ["d"], phases: .down) { press in
            guard press.modifiers.contains(.command), hasDiff else { return .ignored }
            toggleDiff()
            return .handled
        }
        .onKeyPress(keys: ["c"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            onCopy()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            // Return pastes if paste is available, else copies; Shift+Return always copies.
            if canPaste == false || press.modifiers.contains(.shift) {
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

            if hasDiff {
                diffToggle
            }

            closeButton
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
        .frame(height: 44)
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

    // MARK: - Dynamic Dimensions

    /// What the body actually renders — the diff is longer than the result (it keeps the removed
    /// characters), so the card must be measured against it, not against `payload.text`.
    private var measuredText: String {
        if showsDiff, hasDiff {
            return diffSegments.map(\.text).joined()
        }
        return payload.text
    }

    private var dynamicCardWidth: CGFloat {
        preferredSize?.width ?? PopupMetrics.aiCardIdealWidth
    }

    private static let headerHeight: CGFloat = 32.0
    private static let headerTopPadding: CGFloat = 14.0
    private static let gapAfterHeader: CGFloat = 14.0
    private static let topInset: CGFloat = headerTopPadding + headerHeight + gapAfterHeader
    private static let bottomInset: CGFloat = 42.0

    private var naturalContentHeight: CGFloat {
        let textToMeasure = measuredText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToMeasure.isEmpty else { return PopupMetrics.aiCardMinHeight }
        let availableWidth = PopupMetrics.aiCardIdealWidth - 32
        let font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3.5
        let rect = (textToMeasure as NSString).boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        return ceil(rect.height) + Self.topInset + Self.bottomInset
    }

    private var dynamicCardHeight: CGFloat {
        if let preferredSize { return preferredSize.height }
        return min(max(naturalContentHeight, PopupMetrics.aiCardMinHeight), PopupMetrics.aiCardMaxHeight)
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
                .padding(.horizontal, 16)
                .padding(.top, Self.topInset)
                .padding(.bottom, Self.bottomInset)
        }
        .frame(height: dynamicCardHeight)
    }

    @ViewBuilder
    private var bodyText: some View {
        if showsDiff, hasDiff {
            Text(diffAttributedText)
        } else {
            Text(payload.text)
                .foregroundColor(payload.isError ? Color.red : Color.primary)
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
        .padding(.bottom, 10)
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

