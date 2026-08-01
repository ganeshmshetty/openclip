import Foundation
import Core

extension OpenClipSnippetParser {
    public static func parse(snippet: String) async -> (any Action)? {
        return await parse(snippet: snippet, factory: DefaultActionFactory())
    }
}
