import XCTest
import Combine
@testable import Core
@testable import OpenClip

@MainActor
final class CurrencyConversionTests: XCTestCase {
    private let en = Locale(identifier: "en_US")
    private var date: Date { ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")! }
    private func data(_ rates: [CurrencyRate]) throws -> Data { try JSONEncoder().encode(rates) }
    private var usdRate: CurrencyRate { CurrencyRate(date: "2026-10-08", base: "SAR", quote: "USD", rate: Decimal(string: "0.266666666666666666")!) }

    func testArabicAndWesternStandaloneAmounts() {
        for input in ["USD 1,234.50", "1,234.50 USD", "$1,234.50", "١٬٢٣٤٫٥٠ USD", "\u{200f}١٢٣٤٫٥٠ USD", "1\u{202f}234,50 USD"] {
            let amount = CurrencyAmount.parse(input, locale: en)
            XCTAssertEqual(amount?.code, "USD", input)
            XCTAssertEqual(amount?.value, Decimal(string: "1234.50"), input)
        }
        XCTAssertEqual(CurrencyAmount.parse("١٠٠ ر.س", locale: en)?.code, "SAR")
        XCTAssertEqual(CurrencyAmount.parse("1.234,50 EUR", locale: Locale(identifier: "de_DE"))?.value, Decimal(string: "1234.50"))
        XCTAssertEqual(CurrencyAmount.parse("-50 USD", locale: en)?.value, -50)
        XCTAssertEqual(CurrencyAmount.parse("-$50", locale: en)?.value, -50)
        XCTAssertEqual(CurrencyAmount.parse("0 USD", locale: en)?.value, 0)
    }

    func testRejectsAmbiguousMultipleMalformedOrUnlabelledAmounts() {
        for input in ["100", "100 USD + 50 EUR", "Price: $100", "$12 34", "$1,23,456", "$1.2.3", "100 ¥", "100 ريال", "USD NaN", "USD 1e20", "USD 1 2", "10 USD EUR"] {
            XCTAssertNil(CurrencyAmount.parse(input, locale: en), input)
        }
        XCTAssertEqual(CurrencyAmount.parse("$50", dollarCurrency: "CAD", locale: en)?.code, "CAD")
        XCTAssertEqual(CurrencyAmount.parse("US$50", dollarCurrency: "CAD", locale: en)?.code, "USD")
    }

    func testMinorUnitsAndRounding() {
        XCTAssertEqual(CurrencyConversionAction.format(Decimal(string: "1.005")!, code: "SAR", locale: en), "1.01 SAR")
        XCTAssertEqual(CurrencyConversionAction.format(Decimal(string: "1.5")!, code: "JPY", locale: en), "2 JPY")
        XCTAssertEqual(CurrencyConversionAction.format(Decimal(string: "1.2345")!, code: "KWD", locale: en), "1.235 KWD")
        XCTAssertEqual(CurrencyConversionAction.format(Decimal(string: "-1.005")!, code: "SAR", locale: en), "-1.01 SAR")
    }

    func testCurrencyLiteralsDoNotAppearAsCalculations() {
        let calculate = CalculateAction()
        for input in ["-$50", "$-50", "-50 €", "+100 USD"] {
            XCTAssertNotNil(CurrencyAmount.parse(input, locale: en))
            XCTAssertFalse(calculate.isEnabled(for: ActionContext(selection: SelectionContext(text: input))))
            XCTAssertNil(calculate.evaluateSynchronously(input))
        }
        XCTAssertEqual(calculate.evaluateSynchronously("$50 + $20"), "70")
    }

    func testRateAgeAndValidationUseEachObservationDate() {
        let amount = CurrencyAmount.parse("100 USD", locale: en)!
        XCTAssertNotNil(usdRate.convert(amount, at: date))
        for rate in [
            CurrencyRate(date: "2026-09-01", base: "SAR", quote: "USD", rate: 1),
            CurrencyRate(date: "2026-11-01", base: "SAR", quote: "USD", rate: 1),
            CurrencyRate(date: "2026-10-08", base: "SAR", quote: "USD", rate: 0),
            CurrencyRate(date: "2026-10-08", base: "SAR", quote: "USD", rate: -1),
            CurrencyRate(date: "bad", base: "SAR", quote: "USD", rate: 1)
        ] { XCTAssertNil(rate.convert(amount, at: date)) }
    }

    func testRequestContainsOnlyTargetAndCacheSurvivesRestart() async throws {
        let url = CurrencyRateStore.requestURL(target: "SAR")!
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "base", value: "SAR")])
        XCTAssertNil(CurrencyRateStore.requestURL(target: "USD&amount=secret"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("rates.json")
        let payload = try data([usdRate])
        let now = date
        let rates = CurrencyRateStore(cacheURL: cache, now: { now }, fetch: { _ in payload })
        await rates.refresh(target: "SAR").value
        XCTAssertEqual(rates.rate(from: "USD", to: "SAR"), usdRate)
        let offline = CurrencyRateStore(cacheURL: cache, now: { now.addingTimeInterval(2 * 86_400) }, fetch: { _ in throw URLError(.notConnectedToInternet) })
        await offline.refresh(target: "SAR").value
        XCTAssertNotNil(offline.rate(from: "USD", to: "SAR"))
        XCTAssertTrue(offline.failedTargets.contains("SAR"))
        let expired = CurrencyRateStore(cacheURL: cache, now: { now.addingTimeInterval(8 * 86_400) })
        XCTAssertNil(expired.rate(from: "USD", to: "SAR"))
    }

    func testInlinePreviewAndCopyKeepMetadataOutOfClipboard() async throws {
        let now = date
        let payload = try data([usdRate])
        let rates = CurrencyRateStore(now: { now }, fetch: { _ in payload })
        let settings = MemorySettingsStore()
        settings.set(CurrencyConversionAction.optionKey("targetCurrency"), value: "SAR")
        let action = CurrencyConversionAction(store: settings, rates: rates, locale: en, now: { now })
        let context = ActionContext(selection: SelectionContext(text: "$100"))
        XCTAssertTrue(action.isContextual)
        XCTAssertTrue(action.isEnabled(for: context))
        XCTAssertNil(action.preview(for: context))
        await rates.refresh(target: "SAR").value
        let preview = try XCTUnwrap(action.preview(for: context))
        XCTAssertEqual(preview.label, "≈ 375.00 SAR")
        XCTAssertEqual(preview.result.textValue, "375.00 SAR")
        XCTAssertTrue(preview.result.textDetail?.contains("Frankfurter") == true)
        let primary = ActionResultDelivery.resolve(raw: preview.result, clickIntent: .primary, canPaste: true, recommendedResult: .preview)
        XCTAssertNotNil(primary.result.textDetail)
        let secondary = ActionResultDelivery.resolve(raw: preview.result, clickIntent: .secondary, canPaste: true, recommendedResult: .preview)
        guard case .copy(let copied) = secondary.result else { return XCTFail("Expected copy") }
        XCTAssertEqual(copied, "375.00 SAR")
        let paste = ActionResultDelivery.resolve(raw: preview.result, clickIntent: .primary, canPaste: true, preference: .paste)
        guard case .paste(let pasted) = paste.result else { return XCTFail("Expected paste") }
        XCTAssertEqual(pasted, copied)
        settings.set(CurrencyConversionAction.optionKey("targetCurrency"), value: "USD")
        XCTAssertFalse(action.isEnabled(for: context))
        XCTAssertNil(action.preview(for: context))
    }

    func testLivePreviewsNeverEnterGenericMemoization() async throws {
        let now = date
        let payload = try data([usdRate])
        let rates = CurrencyRateStore(now: { now }, fetch: { _ in payload })
        let settings = MemorySettingsStore()
        settings.set(CurrencyConversionAction.optionKey("targetCurrency"), value: "SAR")
        let action = CurrencyConversionAction(store: settings, rates: rates, locale: en, now: { now })
        let context = ActionContext(selection: SelectionContext(text: "100 USD"))
        let evaluator = InlineResultEvaluator()
        evaluator.prewarm(actions: [action], context: context)
        await rates.refresh(target: "SAR").value
        XCTAssertNil(evaluator.prewarmedResult(for: action, textHash: context.selection.text.hashValue))
        settings.set(.disabledActionIDs, value: [action.id])
        XCTAssertNil(action.preview(for: context))
    }

    func testConcurrentRequestsCoalesceAndWarmConversionsNeverFetch() async throws {
        var clock = date
        let stub = CurrencyFetchStub(payload: try data([usdRate]))
        let rates = CurrencyRateStore(now: { clock }, fetch: { try await stub.fetch($0) })
        let pending = (0..<10).map { _ in rates.refresh(target: "SAR") }
        for task in pending { await task.value }
        var count = await stub.count
        XCTAssertEqual(count, 1)
        for _ in 0..<20 { await rates.refresh(target: "SAR").value }
        count = await stub.count
        XCTAssertEqual(count, 1)

        clock.addTimeInterval(86_401)
        await stub.setFailure(true)
        await rates.refresh(target: "SAR").value
        XCTAssertTrue(rates.failedTargets.contains("SAR"))
        XCTAssertNotNil(rates.rate(from: "USD", to: "SAR"))
        await rates.refresh(target: "SAR").value
        count = await stub.count
        XCTAssertEqual(count, 2, "Failure must not trigger repeated requests per selection")
        clock.addTimeInterval(301)
        await rates.refresh(target: "SAR").value
        count = await stub.count
        XCTAssertEqual(count, 3)
    }

    func testLoadingUnavailableStaleAndExpiredStates() async throws {
        var clock = date
        let stub = CurrencyFetchStub(payload: try data([usdRate]))
        let rates = CurrencyRateStore(now: { clock }, fetch: { try await stub.fetch($0) })
        let settings = MemorySettingsStore()
        settings.set(CurrencyConversionAction.optionKey("targetCurrency"), value: "SAR")
        let action = CurrencyConversionAction(store: settings, rates: rates, locale: en, now: { clock })
        let context = ActionContext(selection: SelectionContext(text: "100 USD"))
        action.preparePreview(for: context)
        XCTAssertEqual(action.preview(for: context)?.label, "…")
        XCTAssertNil(action.preview(for: context)?.result.textValue)
        await rates.refresh(target: "SAR").value
        XCTAssertEqual(action.preview(for: context)?.label, "≈ 375.00 SAR")

        clock.addTimeInterval(4 * 86_400)
        await stub.setFailure(true)
        await rates.refresh(target: "SAR").value
        let old = try XCTUnwrap(action.preview(for: context))
        XCTAssertEqual(old.label, "◷ 375.00 SAR")
        XCTAssertTrue(old.result.textDetail?.contains("more than three days") == true)
        XCTAssertTrue(old.result.textDetail?.contains("Using saved rates") == true)

        clock.addTimeInterval(4 * 86_400)
        XCTAssertEqual(action.preview(for: context)?.label, "Rate unavailable")
        XCTAssertNil(action.preview(for: context)?.result.textValue)
    }

    func testFirstSettingsChangeInvalidatesAndCancelsPendingPreview() async throws {
        let now = date
        let stub = CurrencyFetchStub(payload: try data([usdRate]))
        let rates = CurrencyRateStore(now: { now }, fetch: { try await stub.fetch($0) })
        let settings = MemorySettingsStore()
        settings.set(CurrencyConversionAction.optionKey("targetCurrency"), value: "SAR")
        let action = CurrencyConversionAction(store: settings, rates: rates, locale: en, now: { now })
        let context = ActionContext(selection: SelectionContext(text: "100 USD"))
        let pending = rates.refresh(target: "SAR")
        let changed = expectation(description: "First option change invalidates preview")
        let subscription = action.previewChanges.sink { changed.fulfill() }
        settings.set(CurrencyConversionAction.optionKey("targetCurrency"), value: "USD")
        await fulfillment(of: [changed], timeout: 1)
        await pending.value
        XCTAssertNil(action.preview(for: context))
        XCTAssertNil(rates.rate(from: "USD", to: "SAR"))
        XCTAssertFalse(rates.isRefreshing(target: "SAR"))
        subscription.cancel()
    }

    func testInvalidProviderTablesCannotReplaceRates() async throws {
        let now = date
        let payloads = try [[usdRate, usdRate], [CurrencyRate(date: "2026-10-08", base: "EUR", quote: "USD", rate: 1)]].map(data)
        for payload in payloads {
            let rates = CurrencyRateStore(now: { now }, fetch: { _ in payload })
            await rates.refresh(target: "SAR").value
            XCTAssertTrue(rates.failedTargets.contains("SAR"))
            XCTAssertNil(rates.rate(from: "USD", to: "SAR"))
        }
    }

    func testChangedInlineResultIsNeverCopiedAsOldText() {
        let store = PopupModeStore()
        store.inlineResults["currency"] = "≈ 375.00 SAR"
        store.inlineOutputs["currency"] = .annotatedText(text: "375.00 SAR", detail: "date")
        store.inlineValidators["currency"] = { false }
        let result = store.inlineOutput(for: "currency")!
        XCTAssertNil(result.textValue)
        let delivery = ActionResultDelivery.resolve(raw: result, clickIntent: .secondary, canPaste: false)
        guard case .toast = delivery.result else { return XCTFail("A changed preview must ask for a fresh selection") }
    }
}

private actor CurrencyFetchStub {
    let payload: Data
    var count = 0
    private var shouldFail = false

    init(payload: Data) { self.payload = payload }
    func setFailure(_ value: Bool) { shouldFail = value }
    func fetch(_ url: URL) async throws -> Data {
        count += 1
        try await Task.sleep(for: .milliseconds(40))
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return payload
    }
}
