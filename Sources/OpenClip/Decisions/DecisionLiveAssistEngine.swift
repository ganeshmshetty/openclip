// DecisionLiveAssistEngine.swift
// OpenClip
//
// Opt-in Live assist: debounce 100–300ms, cancel in-flight, prefer local Laya, suggest-not-rewrite.
// Full any-field AX focus-value monitoring is partially stubbed (see Settings status).
import Foundation
import Core

public struct DecisionLiveSuggestion: Sendable, Equatable {
    public var toolID: String
    public var title: String
    public var chips: [String]
    public var confidence: Double?
    public var kind: Kind

    public enum Kind: String, Sendable, Equatable {
        case smartHint
        case safeToSharePill
        case paletteIntent
    }

    public init(toolID: String, title: String, chips: [String], confidence: Double? = nil, kind: Kind) {
        self.toolID = toolID
        self.title = title
        self.chips = chips
        self.confidence = confidence
        self.kind = kind
    }
}

/// Debounced Live assist runner. Privacy: off by default; prefers local Laya; never rewrites text.
@MainActor
public final class DecisionLiveAssistEngine: ObservableObject {
    public static let shared = DecisionLiveAssistEngine()

    @Published public private(set) var latestSuggestion: DecisionLiveSuggestion?
    @Published public private(set) var statusMessage: String = ""
    @Published public private(set) var axFocusMonitoringAvailable: Bool = false

    private var inFlight: Task<Void, Never>?
    private var debounceWorkItem: DispatchWorkItem?

    private init() {
        // TODO: Wire AX focused UI element value observer when a stable focus-value path is ready.
        // Until then the setting + debounce engine ship; Settings shows this status.
        axFocusMonitoringAvailable = false
        statusMessage = String(localized: "Live assist watches the current OpenClip selection only. Full any-field AX focus monitoring is not enabled yet.")
    }

    public var isEnabled: Bool {
        DecisionServiceManager.shared.isLiveAssistActive && DecisionServiceManager.shared.isDecisionsEnabled
    }

    /// Privacy copy for Preferences.
    public static let privacyBlurb = String(localized: """
    Live assist is off by default. Turn it on here, or for 30 minutes, an hour, or until tomorrow from the \
    menu bar's Live Assist submenu. When enabled it sends only the current selection (or palette query) \
    to your configured Decision provider — preferring local Laya when available. It never rewrites text; \
    it only suggests chips (Smart hint, Safe-to-share pill, palette intent). Keys stay in SecretStore. \
    Full monitoring of arbitrary focused fields via Accessibility APIs is not enabled yet.
    """)

    public func cancel() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        inFlight?.cancel()
        inFlight = nil
    }

    /// Stops pending and in-flight work and drops the last suggestion, e.g. when the menu bar's
    /// timed window ends or Live assist is switched off.
    public func deactivate() {
        cancel()
        latestSuggestion = nil
    }

    /// Schedule a suggestion for the given selection text.
    public func schedule(selectionText: String, kind: DecisionLiveSuggestion.Kind = .smartHint) {
        cancel()
        guard isEnabled else {
            latestSuggestion = nil
            return
        }
        let ms = DecisionServiceManager.shared.liveAssistDebounceMS
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.run(selectionText: selectionText, kind: kind)
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: work)
    }

    private func run(selectionText: String, kind: DecisionLiveSuggestion.Kind) async {
        let trimmed = selectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            latestSuggestion = nil
            return
        }
        let toolID: String
        switch kind {
        case .safeToSharePill: toolID = "safe_to_share"
        case .paletteIntent, .smartHint: toolID = "smart_action"
        }
        guard let tool = DecisionServiceManager.shared.tools.first(where: { $0.id == toolID && $0.isEnabled }) else {
            return
        }
        let task = Task { @MainActor in
            do {
                let provider = await DecisionServiceManager.shared.liveAssistProvider()
                let request = DecisionQuestionPacker.pack(
                    state: trimmed,
                    questions: Array(tool.questions.prefix(1)),
                    toolID: tool.id
                )
                let response = try await provider.decide(request)
                guard !Task.isCancelled else { return }
                let chips = response.answers.map(\.value.displayLabel)
                latestSuggestion = DecisionLiveSuggestion(
                    toolID: tool.id,
                    title: tool.title,
                    chips: chips,
                    confidence: response.confidence ?? response.answers.first?.confidence,
                    kind: kind
                )
                Log.decisions.info("Live assist suggestion ready for \(tool.id, privacy: .public)")
            } catch is CancellationError {
                // ignore
            } catch {
                Log.decisions.notice("Live assist skipped: \(error.localizedDescription)")
                latestSuggestion = nil
            }
        }
        inFlight = task
        await task.value
    }
}
