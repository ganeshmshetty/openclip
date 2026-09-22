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

    private let monitor: FocusedTextMonitor
    private var inFlight: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
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
    /// simple enough to answer in one pass (a tree or a bulk tool is a deliberate, explicit run).
    public var quickAssistTools: [DecisionToolPreset] {
        DecisionServiceManager.shared.tools.filter {
            $0.isEnabled && $0.showsInQuickAssist && $0.treeID == nil && $0.bulkMode == .none && !$0.questions.isEmpty
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
        rows = []
        statusLine = nil
        lastJudgedText = nil
    }

    /// Debounced entry point: the focused field's text changed.
    public func schedule(text: String) {
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumCharacters else {
            rows = []
            statusLine = String(localized: "Start typing and answers appear here.")
            lastJudgedText = nil
            return
        }
        guard trimmed != lastJudgedText else { return }

        statusLine = nil
        rows = tools.map { QuickAssistRow(id: $0.id, title: $0.title, state: .running) }

        let ms = DecisionServiceManager.shared.liveAssistDebounceMS
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            guard !Task.isCancelled, let self else { return }
            self.run(text: trimmed, tools: tools)
        }
    }

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
