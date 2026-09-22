// DecisionLiveAssistEngine.swift
// OpenClip
//
// Runs the Decision tools marked "Show in Quick Assist" against whatever the user is typing, and
// publishes one row per tool for the floating Quick Assist window.
//
// Every tool's primary question goes into a single provider request: a System One model answers N
// typed questions in one forward pass, so five tools cost what one costs (tens of milliseconds on
// Laya). Question ids are namespaced per tool on the way out and matched back on the way in.
//
// Typing is debounced, and a new keystroke cancels the request in flight, so only the text the user
// has settled on is ever judged.
//
// What is being judged is always visible in the window as the "context": the field being typed in,
// plus any selections added with the + button. It clears itself `contextIdleTimeout` after the last
// keystroke so a stale sentence is never left on screen being re-judged, and the ✕ next to it
// clears it immediately.
import Foundation
import Core

@MainActor
public final class DecisionLiveAssistEngine: ObservableObject {
    public static let shared = DecisionLiveAssistEngine()

    /// One row per Quick Assist tool, in the order they appear in Settings.
    @Published public private(set) var rows: [QuickAssistRow] = []
    /// Status line for the window when there is nothing to show: no tools, no text, or a provider
    /// that cannot answer.
    @Published public private(set) var statusLine: String?

    /// True when the Accessibility permission needed to read the focused field has been granted.
    public var axFocusMonitoringAvailable: Bool { monitor.isAvailable }

    /// Selections added with the + button. They stay until the context is cleared.
    @Published public private(set) var pinnedContext: [String] = []
    /// The text of the field being typed in right now.
    @Published public private(set) var typedText: String = ""

    /// Everything Quick Assist is judging, exactly as the window shows it.
    public var context: String {
        (pinnedContext + [typedText]).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The context clears itself this long after the last keystroke or added selection.
    public var contextIdleTimeout: TimeInterval = 10

    private let monitor: FocusedTextMonitor
    private var inFlight: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var lastJudgedText: String?

    /// Question id prefix that namespaces a tool's question inside the batched request.
    static let questionPrefix = "qa."

    public init(monitor: FocusedTextMonitor = .shared) {
        self.monitor = monitor
    }

    /// Live assist is on when the Settings toggle is on or the menu bar opened a timed window, and
    /// Decision Tools themselves are enabled.
    public var isEnabled: Bool {
        DecisionServiceManager.shared.isLiveAssistActive && DecisionServiceManager.shared.isDecisionsEnabled
    }

    /// Privacy copy for Preferences.
    public static let privacyBlurb = String(localized: """
    Live assist is off by default. Turn it on here, or for 30 minutes, an hour, or until tomorrow from the \
    menu bar's Live Assist submenu. When enabled, OpenClip reads the text of the field you are typing in \
    through Accessibility and sends it to your configured Decision provider — staying on this Mac when that \
    provider is Laya. Password fields are never read, nothing is stored, and it only ever shows answers in \
    the Quick Assist window; it never rewrites or types anything.
    """)

    /// The tools that answer in the Quick Assist window: enabled, marked for Quick Assist, and
    /// answerable in one pass (a bulk tool is a deliberate, explicit run).
    public var quickAssistTools: [DecisionToolPreset] {
        DecisionServiceManager.shared.tools.filter {
            $0.isEnabled && $0.showsInQuickAssist && $0.bulkMode == .none && !$0.questions.isEmpty
        }
    }

    // MARK: - Running

    public func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
        inFlight?.cancel()
        inFlight = nil
    }

    /// Stops pending and in-flight work and drops every row, e.g. when the menu bar's timed window
    /// ends or Live assist is switched off.
    public func deactivate() {
        cancel()
        idleTask?.cancel()
        idleTask = nil
        pinnedContext = []
        typedText = ""
        rows = []
        statusLine = nil
        lastJudgedText = nil
    }

    /// The focused field's text changed. It replaces the typed part of the context, so only the
    /// latest thing being written is judged.
    public func updateTyped(_ text: String) {
        typedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        contextDidChange()
    }

    /// The + button: judge this selection alongside whatever is being typed.
    public func addSelection(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !pinnedContext.contains(trimmed) else { return }
        pinnedContext.append(trimmed)
        contextDidChange()
    }

    /// The ✕ next to the context, and the idle reset: forget everything and wait for new text.
    public func clearContext() {
        cancel()
        idleTask?.cancel()
        idleTask = nil
        pinnedContext = []
        typedText = ""
        rows = []
        lastJudgedText = nil
        statusLine = isEnabled ? Self.waitingStatus : nil
    }

    private func contextDidChange() {
        restartIdleTimer()
        judge()
    }

    /// Restarts the countdown that clears the context when the user stops typing.
    private func restartIdleTimer() {
        idleTask?.cancel()
        idleTask = nil
        guard contextIdleTimeout > 0, !context.isEmpty else { return }
        let timeout = contextIdleTimeout
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.clearContext()
        }
    }

    /// Debounced run over the current context.
    private func judge() {
        cancel()
        guard isEnabled else {
            rows = []
            return
        }
        let tools = quickAssistTools
        guard !tools.isEmpty else {
            rows = []
            statusLine = String(localized: "No tools yet. Turn on “Show in Quick Assist” for a tool in Settings → Decisions.")
            return
        }
        let text = context
        guard text.count >= Self.minimumCharacters else {
            rows = []
            statusLine = Self.waitingStatus
            lastJudgedText = nil
            return
        }
        guard text != lastJudgedText else { return }

        statusLine = nil
        rows = tools.map { QuickAssistRow(id: $0.id, title: $0.title, state: .running) }

        let ms = DecisionServiceManager.shared.liveAssistDebounceMS
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            guard !Task.isCancelled, let self else { return }
            self.run(text: text, tools: tools)
        }
    }

    static let waitingStatus = String(localized: "Start typing, or add a selection with +.")

    private func run(text: String, tools: [DecisionToolPreset]) {
        inFlight?.cancel()
        inFlight = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let provider = await DecisionServiceManager.shared.liveAssistProvider()
                let request = DecisionQuestionPacker.pack(
                    state: text,
                    questions: Self.batchedQuestions(for: tools),
                    toolID: "quick_assist"
                )
                let response = try await provider.decide(request)
                guard !Task.isCancelled else { return }
                self.lastJudgedText = text
                self.rows = Self.rows(from: response, tools: tools)
                self.statusLine = nil
                Log.decisions.info("Quick Assist answered \(tools.count, privacy: .public) tool(s)")
            } catch is CancellationError {
                // A newer keystroke won; its own run publishes the rows.
            } catch {
                guard !Task.isCancelled else { return }
                self.rows = []
                self.statusLine = error.localizedDescription
                Log.decisions.notice("Quick Assist skipped: \(error.localizedDescription)")
            }
        }
    }

    /// Each tool's primary question, id-namespaced so one request can carry them all.
    static func batchedQuestions(for tools: [DecisionToolPreset]) -> [DecisionQuestion] {
        tools.compactMap { tool in
            guard var question = tool.questions.first else { return nil }
            question.id = questionPrefix + tool.id
            return question
        }
    }

    /// Maps a batched response back onto one row per tool, honouring each tool's own confidence
    /// threshold so an unsure answer reads as a question mark rather than a wrong yes/no.
    static func rows(from response: DecisionResponse, tools: [DecisionToolPreset]) -> [QuickAssistRow] {
        tools.map { tool in
            guard let answer = response.answer(for: questionPrefix + tool.id) else {
                return QuickAssistRow(id: tool.id, title: tool.title, state: .unsure)
            }
            let confidence = answer.confidence ?? response.confidence
            let presentation = DecisionPresentation(
                toolID: tool.id,
                toolTitle: tool.title,
                answers: [answer],
                confidence: confidence,
                requiresConfirmation: (confidence ?? 1) < tool.confirmBelowConfidence
            )
            return QuickAssistRow(id: tool.id, title: tool.title, state: DecisionInlineState(presentation))
        }
    }

    /// Below this many characters there is nothing worth judging yet.
    static let minimumCharacters = 12
}
