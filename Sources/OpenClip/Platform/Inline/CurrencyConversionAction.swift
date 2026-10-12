import Foundation
import Combine
import Core

@MainActor
final class CurrencyConversionAction: ConfigurableAction, LiveInlineAction, ContextualActionDescribing {
    nonisolated static let actionID = "builtin.convertCurrency"
    nonisolated let id = CurrencyConversionAction.actionID
    nonisolated var title: String { String(localized: "Convert Currency") }
    nonisolated let icon = ActionIcon.symbol("dollarsign.arrow.circlepath")
    nonisolated let preferenceIconName = "dollarsign.arrow.circlepath"
    nonisolated var chrome: ActionChrome { ActionChrome(isInlineResult: true, outputKind: .text, recommendedResult: .preview) }
    nonisolated var contextualDescription: String { String(localized: "Amounts with currency codes or symbols") }
    nonisolated var keywords: [String] { ["currency", "exchange", "money", "SAR", "USD", "EUR", "ريال", "عملات"] }
    nonisolated var actionOptions: [ExtensionOption] {
        [
            ExtensionOption(identifier: "targetCurrency", label: String(localized: "Target Currency"), type: .multiple,
                defaultValue: Self.defaultTarget, options: CurrencyAmount.supportedCodes),
            ExtensionOption(identifier: "dollarCurrency", label: String(localized: "Currency for $"), type: .multiple,
                defaultValue: "USD", options: ["USD", "CAD", "AUD", "NZD", "HKD", "SGD"])
        ]
    }
    nonisolated static var defaultTarget: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return CurrencyAmount.supportedCodes.contains(code) ? code : "USD"
    }

    private let store: any SettingsStore
    private let rates: CurrencyRateStore
    private let now: () -> Date
    private let locale: Locale
    private let changes = PassthroughSubject<Void, Never>()
    private var subscriptions = Set<AnyCancellable>()
    var previewChanges: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }

    init(store: any SettingsStore = DefaultSettingsStore.shared, rates: CurrencyRateStore = .shared,
         locale: Locale = .current, now: @escaping () -> Date = Date.init) {
        self.store = store; self.rates = rates; self.locale = locale; self.now = now
        rates.$revision.dropFirst().sink { [weak self] _ in self?.changes.send() }.store(in: &subscriptions)
        for key in [Self.optionKey("targetCurrency"), Self.optionKey("dollarCurrency")] {
            store.publisher(for: key).receive(on: DispatchQueue.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.rates.cancelRequests(); self?.changes.send() }
            }.store(in: &subscriptions)
        }
        store.publisher(for: .disabledActionIDs).receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.rates.cancelRequests(); self?.changes.send() }
        }.store(in: &subscriptions)
    }

    nonisolated static func optionKey(_ name: String) -> SettingKey<String> { .actionOption(actionID: actionID, optionID: name) }
    var target: String {
        let saved = store.get(Self.optionKey("targetCurrency")).uppercased()
        return CurrencyAmount.supportedCodes.contains(saved) ? saved : Self.defaultTarget
    }
    private var dollar: String {
        let saved = store.get(Self.optionKey("dollarCurrency")).uppercased()
        return ["USD", "CAD", "AUD", "NZD", "HKD", "SGD"].contains(saved) ? saved : "USD"
    }
    private func amount(_ context: ActionContext) -> CurrencyAmount? {
        CurrencyAmount.parse(context.selection.text, dollarCurrency: dollar, locale: locale)
    }
    func isEnabled(for context: ActionContext) -> Bool {
        guard !store.get(.disabledActionIDs).contains(id), let amount = amount(context) else { return false }
        return amount.code != target
    }
    func preparePreview(for context: ActionContext) {
        guard isEnabled(for: context) else { return }
        _ = rates.refresh(target: target)
    }
    func preview(for context: ActionContext) -> InlineActionPreview? {
        guard isEnabled(for: context), let amount = amount(context) else { return nil }
        guard let rate = rates.rate(from: amount.code, to: target),
              let value = rate.convert(amount, at: now()) else {
            if rates.isRefreshing(target: target) {
                return InlineActionPreview(label: "…", result: .toast(StatusFeedback(
                    message: String(localized: "Updating exchange rates…"), style: .info, keepVisible: true)))
            }
            if rates.snapshots[target] != nil || rates.failedTargets.contains(target) {
                return InlineActionPreview(label: String(localized: "Rate unavailable"), result: unavailableResult)
            }
            return nil
        }
        let output = Self.format(value, code: target, locale: locale)
        let old = rate.observationDate.map { now().timeIntervalSince($0) > 3 * 86_400 } ?? true
        let unavailable = rates.failedTargets.contains(target)
        // Provider dates are calendar dates in UTC, never shift them to the user's time zone.
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateStyle = .medium
        let date = rate.observationDate.map(dateFormatter.string(from:)) ?? rate.date
        var detail = String(localized: "\(Self.format(amount.value, code: amount.code, locale: locale)) → \(target)")
        detail += "\n" + String(localized: "Rate date: \(date)")
        detail += "\n" + String(localized: "Reference rates by Frankfurter. Bank fees are not included.")
        if old { detail += "\n" + String(localized: "This rate is more than three days old.") }
        if unavailable { detail += "\n" + String(localized: "Using saved rates. The latest update was unavailable.") }
        if amount.assumedDollar { detail += "\n" + String(localized: "$ interpreted as \(amount.code)") }
        return InlineActionPreview(label: (old || unavailable ? "◷ " : "≈ ") + output,
            result: .annotatedText(text: output, detail: detail))
    }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        if let preview = preview(for: context), preview.result.textValue != nil { return preview.result }
        guard isEnabled(for: context) else { return .none }
        let requestedTarget = target
        await rates.refresh(target: requestedTarget).value
        guard target == requestedTarget, isEnabled(for: context) else { return .none }
        return preview(for: context)?.result ?? unavailableResult
    }
    private var unavailableResult: ActionResult {
        .toast(StatusFeedback(
            message: String(localized: "No recent exchange rate is available. Connect to the internet and try again."),
            style: .error, keepVisible: true))
    }
    static func format(_ value: Decimal, code: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let digits = formatter.maximumFractionDigits
        var original = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &original, digits, .plain)
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return (formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? NSDecimalNumber(decimal: rounded).stringValue) + " " + code
    }
}
