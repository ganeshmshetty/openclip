import Foundation
import Combine
import Core

@MainActor
final class CurrencyRateStore: ObservableObject {
    static let shared = CurrencyRateStore(cacheURL: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("OpenClip/currency-rates.json"))

    struct Snapshot: Codable {
        let fetchedAt: Date
        let rates: [CurrencyRate]
    }

    @Published private(set) var revision = 0
    private(set) var snapshots: [String: Snapshot] = [:]
    private(set) var failedTargets: Set<String> = []
    private var tasks: [String: Task<Void, Never>] = [:]
    private var lastAttempt: [String: Date] = [:]
    private let cacheURL: URL?
    private let now: () -> Date
    private let fetch: @Sendable (URL) async throws -> Data

    init(cacheURL: URL? = nil, now: @escaping () -> Date = Date.init,
         fetch: @escaping @Sendable (URL) async throws -> Data = CurrencyRateStore.fetchRates) {
        self.cacheURL = cacheURL; self.now = now; self.fetch = fetch
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([String: Snapshot].self, from: data) {
            snapshots = saved.filter { CurrencyAmount.supportedCodes.contains($0.key) && $0.value.fetchedAt <= now() }
        }
    }

    nonisolated static func requestURL(target: String) -> URL? {
        guard CurrencyAmount.supportedCodes.contains(target) else { return nil }
        var url = URLComponents(string: "https://api.frankfurter.dev/v2/rates")!
        url.queryItems = [URLQueryItem(name: "base", value: target)]
        return url.url
    }

    nonisolated static func fetchRates(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 1_000_000 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    func rate(from source: String, to target: String) -> CurrencyRate? {
        snapshots[target]?.rates.first { $0.quote == source && $0.base == target && $0.isUsable(at: now()) }
    }

    func isRefreshing(target: String) -> Bool { tasks[target] != nil }

    func refresh(target: String) -> Task<Void, Never> {
        if let task = tasks[target] { return task }
        let date = now()
        let fresh = snapshots[target].map { date.timeIntervalSince($0.fetchedAt) >= 0 && date.timeIntervalSince($0.fetchedAt) < 86_400 } ?? false
        let backedOff = lastAttempt[target].map { date.timeIntervalSince($0) < 300 } ?? false
        guard !fresh, !backedOff, let url = Self.requestURL(target: target) else { return Task {} }
        lastAttempt[target] = date
        let task = Task { [weak self, fetch] in
            do {
                let data = try await fetch(url)
                try Task.checkCancellation()
                let decoded = try JSONDecoder().decode([CurrencyRate].self, from: data)
                guard let self else { return }
                let valid = decoded.filter { $0.base == target && CurrencyAmount.supportedCodes.contains($0.quote) && $0.isUsable(at: self.now()) }
                guard !valid.isEmpty, Set(valid.map(\.quote)).count == valid.count else { throw URLError(.cannotParseResponse) }
                self.snapshots[target] = Snapshot(fetchedAt: self.now(), rates: valid)
                self.failedTargets.remove(target)
                self.saveCache()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.failedTargets.insert(target)
                Log.presentation.debug("Currency rate refresh unavailable")
            }
            guard let self else { return }
            self.tasks[target] = nil
            self.revision &+= 1
        }
        tasks[target] = task
        revision &+= 1
        return task
    }

    func cancelRequests() {
        for target in tasks.keys { lastAttempt[target] = nil }
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    private func saveCache() {
        guard let cacheURL else { return }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshots).write(to: cacheURL, options: .atomic)
        } catch {
            Log.presentation.debug("Currency rate cache could not be saved")
        }
    }
}
