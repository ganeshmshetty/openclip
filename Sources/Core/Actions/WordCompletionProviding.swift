// WordCompletionProviding.swift
// OpenClip
//
// Defines the protocol for actions that offer inline text auto-completion options based on input text.
import Foundation

public protocol WordCompletionProviding: Action {
    @MainActor
    func fetchCompletions(for text: String) -> [String]
}
