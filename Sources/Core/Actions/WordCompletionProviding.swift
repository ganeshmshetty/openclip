import Foundation

public protocol WordCompletionProviding: Action {
    @MainActor
    func fetchCompletions(for text: String) -> [String]
}
