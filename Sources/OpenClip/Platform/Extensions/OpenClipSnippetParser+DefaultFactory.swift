// OpenClipSnippetParser+DefaultFactory.swift
// OpenClip
//
// Extends OpenClipSnippetParser with convenience factory methods for creating actions directly from snippet files.
import Foundation
import Core

extension OpenClipSnippetParser {
    public static func parse(snippet: String) async -> (any Action)? {
        return await parse(snippet: snippet, factory: DefaultActionFactory())
    }
}
