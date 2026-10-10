import Foundation

public enum ContentType: String, Codable, Sendable, CaseIterable {
    case url, email, date, path, phone, address
}

/// Native recognition results in occurrence order. Duplicates are intentional.
/// Only the types requested by an action are populated; other arrays stay empty.
public struct DetectedContent: Sendable, Equatable {
    public struct DateItem: Sendable, Equatable {
        public let text: String
        public let date: Date
        public let duration: TimeInterval
        public let timeZone: String?
    }

    public struct AddressItem: Sendable, Equatable {
        public let text: String
        public let components: [String: String]
    }

    public var urls: [String] = []
    public var emails: [String] = []
    public var dates: [DateItem] = []
    public var paths: [String] = []
    /// Exact lexical candidates followed by cleaned alternatives, for platform filesystem checks.
    public var pathCandidates: [String] = []
    public var phones: [String] = []
    public var addresses: [AddressItem] = []

    public init() {}

    public func hasItems(_ type: ContentType) -> Bool {
        switch type {
        case .url: !urls.isEmpty
        case .email: !emails.isEmpty
        case .date: !dates.isEmpty
        case .path: !paths.isEmpty
        case .phone: !phones.isEmpty
        case .address: !addresses.isEmpty
        }
    }

    mutating func include(_ type: ContentType, from other: DetectedContent) {
        switch type {
        case .url: urls = other.urls
        case .email: emails = other.emails
        case .date: dates = other.dates
        case .path:
            paths = other.paths
            pathCandidates = other.pathCandidates
        case .phone: phones = other.phones
        case .address: addresses = other.addresses
        }
    }
}

/// One lazy cache per immutable selection. Copies of the selection share the cache.
/// The lock protects all mutation, including detection, across UI and JS threads.
public final class ContentDetectionCache: @unchecked Sendable {
    private let text: String
    private let lock = NSLock()
    private var results: [ContentType: DetectedContent] = [:]

    public init(text: String) { self.text = text }

    public func detect(_ types: [ContentType]) -> DetectedContent {
        lock.withLock {
            var result = DetectedContent()
            for type in Set(types) {
                if results[type] == nil {
                    let detected = NativeContentDetector.detect(text, type: type)
                    results[type] = detected
                    // URLs and emails share the native link scan.
                    if type == .url || type == .email {
                        results[.url] = detected
                        results[.email] = detected
                    }
                }
                if let cached = results[type] { result.include(type, from: cached) }
            }
            return result
        }
    }
}
